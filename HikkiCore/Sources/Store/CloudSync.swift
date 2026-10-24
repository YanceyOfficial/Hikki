import CloudKit
import Foundation
import Network

/// The workspace in iCloud: `CKSyncEngine` over the user's private database (one zone, `Workspace`), carrying the
/// workspace folder file by file as `CloudMirror` describes it. A `File` record holds its path and its contents —
/// both in encrypted fields (end-to-end encrypted: only the user's devices read them), or the contents as an asset
/// when they are large or an attachment. The engine fetches on its own when another device saves (a push) and sends
/// what this device adds to its pending changes; `noteLocalChanges()` adds them after a quiet moment.
///
/// One account per workspace (`CloudMirror.accountAllows`): the engine runs only once the device's account is
/// known to be the workspace's, and stops when it changes — signed out, switched, or signed out and in as someone
/// else (`Status.accountChanged`). Nothing goes up to another account and nothing of its comes down; the pages stay
/// on the device until the user turns iCloud on again for the new account.
public final class CloudSync: CKSyncEngineDelegate, @unchecked Sendable {
    public static let containerID = "iCloud.app.yancey.hikki"
    public static let zoneID = CKRecordZone.ID(zoneName: "Workspace")
    static let recordType = "File"
    /// Contents up to this size travel inside the record; larger ones (and every attachment) as an asset.
    static let inlineLimit = 512 * 1024

    public enum Status: Equatable, Sendable {
        case starting
        /// Up to date at that moment.
        case synced(Date)
        case syncing
        case noAccount
        /// The device signed in to another iCloud account than the one this workspace syncs with.
        case accountChanged
        case quotaFull
        case failed(String)

        /// Something the user should do something about (sign in, free up iCloud storage…).
        public var isTrouble: Bool {
            switch self {
            case .starting, .synced, .syncing: false
            case .noAccount, .accountChanged, .quotaFull, .failed: true
            }
        }

        /// iCloud as the editor's save indicator sees it (`PageSyncState`).
        public var cloud: PageSyncState.Cloud {
            switch self {
            case .starting, .synced, .syncing: .on
            case .noAccount: .trouble(.noAccount)
            case .accountChanged: .trouble(.accountChanged)
            case .quotaFull: .trouble(.quotaFull)
            case .failed: .trouble(.failed)
            }
        }
    }

    private let mirror: CloudMirror
    private let container: CKContainer
    private let lock = NSLock()
    private var engine: CKSyncEngine?
    /// Contents being sent, by record name: what the cloud took is what `saved` records.
    private var inflight: [String: CloudMirror.Outgoing] = [:]
    private var scheduled: DispatchWorkItem?
    /// Between `start` and `stop`; the engine exists only while the account is the workspace's.
    private var running = false
    private var accountObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "app.yancey.hikki.cloud", qos: .utility)
    private let staging: URL
    /// Files changed in the folder from the cloud (the workspace reconciles; editors reload).
    private let onReceived: @Sendable () -> Void
    private let onStatus: @Sendable (Status) -> Void
    /// Where the files of the pages edited in this run stand (the editor's save indicator); under `lock`.
    private var uploads = CloudUploads()
    private let onUploads: @Sendable (CloudUploads) -> Void
    /// Whether the device has a network path: without one nothing goes up, and the indicator says it waits.
    private var pathMonitor: NWPathMonitor?

    public init(
        mirror: CloudMirror, containerID: String = CloudSync.containerID, onReceived: @escaping @Sendable () -> Void,
        onStatus: @escaping @Sendable (Status) -> Void, onUploads: @escaping @Sendable (CloudUploads) -> Void = { _ in }
    ) {
        self.mirror = mirror
        container = CKContainer(identifier: containerID)
        staging = FileManager.default.temporaryDirectory.appending(path: "hikki-cloud", directoryHint: .isDirectory)
        self.onReceived = onReceived
        self.onStatus = onStatus
        self.onUploads = onUploads
    }

    /// Checks the account, then starts the engine (it fetches right away) and queues the zone and whatever changed
    /// here meanwhile.
    public func start() {
        let observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) {
            [weak self] _ in
            Task { await self?.confirmAccount() }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let offline = path.status != .satisfied
            let wasOffline = self.lock.withLock { self.uploads.offline }
            self.updateUploads { $0.setOffline(offline) }
            // Back online: what waited goes up, and what others saved comes down.
            if wasOffline && !offline {
                self.noteLocalChanges(after: 0)
                Task { await self.fetchNow() }
            }
        }
        monitor.start(queue: queue)
        lock.withLock {
            running = true
            accountObserver = observer
            pathMonitor = monitor
        }
        onStatus(.starting)
        Task { await confirmAccount() }
    }

    public func stop() {
        let (observer, monitor) = lock.withLock {
            running = false
            scheduled?.cancel()
            engine = nil
            defer {
                accountObserver = nil
                pathMonitor = nil
            }
            return (accountObserver, pathMonitor)
        }
        monitor?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - The editor's save indicator

    /// The editor saved this page here at `at` and its file has been written since (call it after the workspace's
    /// write-through, `WorkspaceSync.afterQueuedWrites`): the file is followed up to iCloud from now on
    /// (`CloudUploads`).
    public func noteSaved(pageID: String, at: Date) {
        let written = Date.now
        updateUploads { $0.saved(pageID, at: at, written: written) }
    }

    /// Applies `change` to the followed pages and publishes them when anything changed.
    private func updateUploads(_ change: (inout CloudUploads) -> Bool) {
        let published: CloudUploads? = lock.withLock {
            guard change(&uploads) else { return nil }
            uploads.revision += 1
            return uploads
        }
        if let published { onUploads(published) }
    }

    /// Runs the engine when the device's account is the workspace's, stops it when not.
    private func confirmAccount() async {
        let user: CKRecord.ID
        do {
            user = try await container.userRecordID()
        } catch let error as CKError where error.code == .notAuthenticated {
            pause(.noAccount)
            return
        } catch {
            // Offline, most likely: tried again at the next activation (`fetchNow`) or account change.
            Log.warn("cloud account unknown: \(error)", category: "cloud")
            return
        }
        guard mirror.accountAllows(user.recordName) else {
            Log.warn("cloud paused: another account", category: "cloud")
            pause(.accountChanged)
            return
        }
        let started: CKSyncEngine? = lock.withLock {
            guard running, engine == nil else { return nil }
            let serialization = mirror.engineState.flatMap {
                try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
            }
            let engine = CKSyncEngine(
                .init(database: container.privateCloudDatabase, stateSerialization: serialization, delegate: self))
            self.engine = engine
            return engine
        }
        guard let started else { return }
        started.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        noteLocalChanges(after: 0)
    }

    /// No engine, so nothing is sent or fetched until the account is the workspace's again.
    private func pause(_ status: Status) {
        lock.withLock { engine = nil }
        onStatus(status)
    }

    /// Whether events from this engine still count (one dropped at an account change may still report).
    private func isCurrent(_ syncEngine: CKSyncEngine) -> Bool {
        lock.withLock { engine === syncEngine }
    }

    /// Something in the folder may have changed: after `delay` quiet seconds, the changes go up.
    public func noteLocalChanges(after delay: TimeInterval = 1) {
        let work = DispatchWorkItem { [weak self] in self?.queueLocalChanges() }
        lock.withLock {
            scheduled?.cancel()
            scheduled = work
        }
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Sends what is pending now (the app going to the background).
    public func sendNow() async {
        guard let engine = lock.withLock({ engine }) else { return }
        queueLocalChanges()
        do {
            try await engine.sendChanges()
        } catch {
            // Records another device changed first come back as a partial failure; `handleSent` settles each.
            if let error = error as? CKError, error.code == .partialFailure {
                Log.info("cloud send partly refused", category: "cloud", context: ["records": "\(error.partialErrorsByItemID?.count ?? 0)"])
            } else {
                Log.warn("cloud send failed: \(error)", category: "cloud")
            }
        }
    }

    /// Fetches now (app activation; pushes usually get there first).
    public func fetchNow() async {
        if lock.withLock({ running && engine == nil }) { await confirmAccount() }
        guard let engine = lock.withLock({ engine }) else { return }
        do {
            try await engine.fetchChanges()
        } catch {
            Log.warn("cloud fetch failed: \(error)", category: "cloud")
        }
    }

    private func queueLocalChanges() {
        guard let engine = lock.withLock({ engine }) else { return }
        let scannedAt = Date.now
        let changes = mirror.localChanges()
        updateUploads { $0.scanned(changed: changes.map(\.path), at: scannedAt) }
        guard !changes.isEmpty else { return }
        engine.state.add(
            pendingRecordZoneChanges: changes.map { change in
                switch change {
                case .save(let path): .saveRecord(Self.recordID(for: path))
                case .delete(let path): .deleteRecord(Self.recordID(for: path))
                }
            })
        Log.info("cloud changes queued", category: "cloud", context: ["count": "\(changes.count)"])
    }

    static func recordID(for path: String) -> CKRecord.ID {
        CKRecord.ID(recordName: CloudMirror.recordName(for: path), zoneID: zoneID)
    }

    // MARK: - CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard isCurrent(syncEngine) else { return }
        switch event {
        case .stateUpdate(let update):
            mirror.setEngineState(try? JSONEncoder().encode(update.stateSerialization))
        case .accountChange(let change):
            handleAccountChange(change)
        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == Self.zoneID {
                // The zone is gone (the user deleted the app's iCloud data, or end-to-end keys were reset): the
                // pages are still here, so they go up again whole.
                Log.warn("cloud zone deleted", category: "cloud", context: ["reason": "\(deletion.reason)"])
                mirror.forgetCloud()
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                queueLocalChanges()
            }
        case .fetchedRecordZoneChanges(let changes):
            receive(changes.modifications.map(\.record), deletions: changes.deletions.map(\.recordID), syncEngine: syncEngine)
        case .sentRecordZoneChanges(let sent):
            handleSent(sent, syncEngine: syncEngine)
        case .willFetchChanges, .willSendChanges:
            onStatus(.syncing)
        case .didFetchChanges, .didSendChanges:
            onStatus(.synced(.now))
        case .sentDatabaseChanges(let sent):
            for failed in sent.failedZoneSaves {
                Log.error("cloud zone save failed: \(failed.error.code.rawValue)", category: "cloud")
                report(failed.error)
            }
        default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard isCurrent(syncEngine) else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            guard let self else { return nil }
            guard let record = self.record(for: recordID) else {
                // The file went away before it could go up: its deletion is (or will be) queued instead.
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            return record
        }
    }

    // MARK: - Records

    /// The record for a file as it is now, on its last known system fields (so the server can tell a stale save).
    private func record(for id: CKRecord.ID) -> CKRecord? {
        guard let path = mirror.path(forRecordName: id.recordName) ?? pendingPath(for: id), let file = mirror.outgoing(path)
        else { return nil }
        let record = mirror.systemFields(path).flatMap(Self.decodeSystemFields) ?? CKRecord(recordType: Self.recordType, recordID: id)
        record.encryptedValues["path"] = path
        if file.contents.count <= Self.inlineLimit && !path.hasPrefix("assets/") {
            record.encryptedValues["data"] = file.contents
            record["file"] = nil
        } else {
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let copy = staging.appending(path: id.recordName)
                try file.contents.write(to: copy, options: .atomic)
                record["file"] = CKAsset(fileURL: copy)
                record.encryptedValues["data"] = nil
            } catch {
                Log.error("cloud asset staging failed: \(error)", category: "cloud")
                return nil
            }
        }
        record["modified"] = file.modified
        lock.withLock { inflight[id.recordName] = file }
        updateUploads { $0.sending(path, asOf: file.modified) }
        return record
    }

    /// A file new here has no entry yet: its path is found by scanning for the name.
    private func pendingPath(for id: CKRecord.ID) -> String? {
        mirror.listFiles().keys.first { CloudMirror.recordName(for: $0) == id.recordName }
    }

    private func receive(_ records: [CKRecord], deletions: [CKRecord.ID], syncEngine: CKSyncEngine) {
        var touched = false
        var push: [CKRecord.ID] = []
        mirror.batch {
            for record in records {
                guard let path = record.encryptedValues["path"] as? String, let contents = Self.contents(of: record) else {
                    let reason = record.encryptedValues["path"] == nil ? "path" : record["file"] == nil ? "data" : "asset"
                    Log.warn("cloud record unreadable", category: "cloud", context: ["missing": reason])
                    continue
                }
                do {
                    let received = try mirror.receive(path, contents: contents, systemFields: Self.encodeSystemFields(record))
                    touched = touched || received.touched
                    if received.needsPush { push.append(record.recordID) }
                } catch {
                    Log.error("cloud file not written: \(error)", category: "cloud", context: ["kind": CloudMirror.kind(of: path)])
                }
            }
            for id in deletions {
                guard let path = mirror.path(forRecordName: id.recordName) else { continue }
                do {
                    let received = try mirror.receiveDeletion(path)
                    touched = touched || received.touched
                    if received.needsPush { push.append(id) }
                } catch {
                    Log.error("cloud file not removed: \(error)", category: "cloud", context: ["kind": CloudMirror.kind(of: path)])
                }
            }
        }
        if !push.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: push.map { .saveRecord($0) }) }
        // Files merged or copied here (a conflicted page copy) are new files: they go up with the next scan.
        if push.count > 0 { noteLocalChanges() }
        if touched {
            Log.info("cloud changes received", category: "cloud", context: ["records": "\(records.count + deletions.count)"])
            onReceived()
        }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) {
        var refetch = false
        let acknowledged = Date.now
        mirror.batch {
            for record in sent.savedRecords {
                guard let file = lock.withLock({ inflight.removeValue(forKey: record.recordID.recordName) }) else { continue }
                mirror.saved(file, systemFields: Self.encodeSystemFields(record))
                updateUploads { $0.uploaded(file.path, asOf: file.modified, at: acknowledged) }
            }
            for id in sent.deletedRecordIDs {
                if let path = mirror.path(forRecordName: id.recordName) { mirror.deleted(path) }
            }
        }
        for failed in sent.failedRecordSaves {
            let id = failed.record.recordID
            lock.withLock { _ = inflight.removeValue(forKey: id.recordName) }
            let path = failed.record.encryptedValues["path"] as? String
            switch failed.error.code {
            case .serverRecordChanged:
                // Another device saved it first: settle with theirs, then send the result over it. The server's
                // record in the error may come without its asset: then nothing is resent on the old version (it
                // would clash again) — a fetch brings the record whole, and settling it queues the save.
                if let server = failed.error.serverRecord, Self.isReadable(server) {
                    receive([server], deletions: [], syncEngine: syncEngine)
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                } else {
                    refetch = true
                }
                if let path { updateUploads { $0.refused(path, retry: .queued) } }
            case .zoneNotFound:
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                if let path { mirror.lostRecord(path) }
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                if let path { updateUploads { $0.refused(path, retry: .queued) } }
            case .unknownItem:
                if let path { mirror.lostRecord(path) }
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                if let path { updateUploads { $0.refused(path, retry: .queued) } }
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited, .notAuthenticated:
                // the engine tries again on its own
                if let path { updateUploads { $0.refused(path, retry: .retrying) } }
            default:
                Log.error("cloud save failed: \(failed.error.code.rawValue)", category: "cloud")
                report(failed.error)
                if let path { updateUploads { $0.refused(path, retry: .failed) } }
            }
        }
        for (_, error) in sent.failedRecordDeletes where error.code != .unknownItem {
            Log.error("cloud delete failed: \(error.code.rawValue)", category: "cloud")
        }
        try? FileManager.default.removeItem(at: staging)
        if refetch { Task { try? await syncEngine.fetchChanges() } }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signOut:
            pause(.noAccount)
        case .switchAccounts:
            // Stopped at once; it starts again only if the new account is the workspace's (switched back). The
            // engine's kept state is the other account's: an engine made from it again would report this same switch
            // at once (its own state update is dropped once it is paused) — a loop — so it goes, and the next engine
            // starts afresh (a full fetch, which changes nothing that is already here).
            mirror.setEngineState(nil)
            pause(.accountChanged)
            Task { await confirmAccount() }
        case .signIn:
            Task { await confirmAccount() }
        @unknown default:
            Task { await confirmAccount() }
        }
    }

    private func report(_ error: CKError) {
        onStatus(error.code == .quotaExceeded ? .quotaFull : .failed("\(error.code.rawValue)"))
    }

    // MARK: - Coding

    static func isReadable(_ record: CKRecord) -> Bool {
        record.encryptedValues["path"] is String && contents(of: record) != nil
    }

    static func contents(of record: CKRecord) -> Data? {
        if let data = record.encryptedValues["data"] as? Data { return data }
        if let url = (record["file"] as? CKAsset)?.fileURL { return try? Data(contentsOf: url) }
        return nil
    }

    static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
