import CloudKit
import Foundation
import Network

/// What `CloudSync`'s handlers need of `CKSyncEngine.State`: its pending changes. A protocol, so the handlers run in
/// tests without CloudKit's engine (`CloudSyncTests`).
protocol CloudEngineState: AnyObject {
    func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
    func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
    func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
}

extension CKSyncEngine.State: CloudEngineState {}

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
    /// How long a file refused for want of iCloud storage waits before it is tried again, at first; doubled at each
    /// refusal up to `quotaWaitLimit`. A save going through (storage freed) tries them all at once.
    static let quotaWait: TimeInterval = 15 * 60
    static let quotaWaitLimit: TimeInterval = 6 * 60 * 60

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

    /// What a send did, as `handleSent` reads it: built from the engine's event (tests build their own).
    struct SentChanges {
        var saved: [CKRecord] = []
        var failedSaves: [(record: CKRecord, error: CKError)] = []
        var deleted: [CKRecord.ID] = []
        var failedDeletes: [(id: CKRecord.ID, error: CKError)] = []
    }

    /// What a refused save asks for.
    enum SaveFailure: Equatable {
        /// Another device saved the record first: settle with its version.
        case clash
        /// The zone isn't there: made again, and every file goes up.
        case zoneGone
        /// The record isn't there (deleted elsewhere): the file goes up as a new one.
        case recordGone
        /// Not the record's fault (cancelled, or it went down with its batch): sent again.
        case sendAgain
        /// The engine sends it again on its own (network, busy, rate limit, signing in).
        case engineRetries
        /// iCloud storage is full: tried again after a while, or once a save goes through.
        case storageFull
        /// Refused as it is (too large, not accepted…): tried again only once the file changes, or after a relaunch.
        case refused
    }

    private let mirror: CloudMirror
    private let containerID: String
    /// Made when needed, never in tests (a test process has no iCloud entitlement).
    private var container: CKContainer { CKContainer(identifier: containerID) }
    private let lock = NSLock()
    private var engine: CKSyncEngine?
    /// Files being sent, by record name, as read for their record: what the cloud took is what `saved` records.
    private var inflight: [String: CloudMirror.Outgoing] = [:]
    private var scheduled: DispatchWorkItem?
    /// Between `start` and `stop`; the engine exists only while the account is the workspace's.
    private var running = false
    private var accountObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "app.yancey.hikki.cloud", qos: .utility)
    /// This instance's folder for the copies that go up as assets (one per record built, removed once it is sent).
    private let staging: URL
    /// Files changed in the folder from the cloud (the workspace reconciles; editors reload).
    private let onReceived: @Sendable () -> Void
    private let onStatus: @Sendable (Status) -> Void
    /// A failure the user should see — storage full, a refusal — stays shown until a send goes through without one
    /// (the "Synced" after every send no longer hides it at once). Under `lock`.
    private var trouble: Status?
    /// In the send under way: whether anything went up, and whether anything was refused. Under `lock`.
    private var sendWentThrough = false
    private var sendRefused = false
    /// The next wait after "storage full" (`quotaWait`, doubling). Under `lock`.
    private var quotaWait = CloudSync.quotaWait
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
        self.containerID = containerID
        staging = Self.stagingRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        self.onReceived = onReceived
        self.onStatus = onStatus
        self.onUploads = onUploads
    }

    static var stagingRoot: URL {
        FileManager.default.temporaryDirectory.appending(path: "hikki-cloud", directoryHint: .isDirectory)
    }

    /// Checks the account, then starts the engine (it fetches right away) and queues the zone and whatever changed
    /// here meanwhile.
    public func start() {
        removeStagingLeftovers()
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

    /// Copies an earlier run (or an earlier `CloudSync`) left staged — it quit before they were sent.
    private func removeStagingLeftovers() {
        let manager = FileManager.default
        guard let leftovers = try? manager.contentsOfDirectory(at: Self.stagingRoot, includingPropertiesForKeys: nil) else {
            return
        }
        for url in leftovers where url.lastPathComponent != staging.lastPathComponent {
            try? manager.removeItem(at: url)
        }
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

    /// Files waiting after "storage full" are tried now (the user pulled to refresh, or came back to the app).
    public func retryHeldBack() {
        if mirror.releaseTimedHolds() { noteLocalChanges(after: 0) }
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
        queueLocalChanges(into: engine.state)
    }

    /// Scans the folder and adds what changed since it last agreed with the cloud to the engine's pending changes.
    func queueLocalChanges(into state: some CloudEngineState) {
        let scannedAt = Date.now
        let changes = mirror.localChanges(now: scannedAt)
        updateUploads { $0.scanned(changed: changes.map(\.path), at: scannedAt) }
        guard !changes.isEmpty else { return }
        state.add(
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

    // MARK: - Status

    /// Shows `status` — unless a failure the user should see still stands.
    private func publish(_ status: Status) {
        let shown = lock.withLock { trouble ?? status }
        onStatus(shown)
    }

    /// A failure the user should see: shown, and kept until a send goes through without one.
    private func report(_ error: CKError) {
        let status: Status = error.code == .quotaExceeded ? .quotaFull : .failed("\(error.code.rawValue)")
        lock.withLock {
            trouble = status
            sendRefused = true
        }
        onStatus(status)
    }

    /// The engine starts sending.
    func sendStarted() {
        lock.withLock {
            sendWentThrough = false
            sendRefused = false
        }
        publish(.syncing)
    }

    /// The send is over. One that took something without a refusal clears a standing failure — and, storage being
    /// free again, the files held back for want of it go now.
    func sendEnded() {
        let cleared: Bool = lock.withLock {
            guard sendWentThrough, !sendRefused else { return false }
            trouble = nil
            quotaWait = Self.quotaWait
            return true
        }
        if cleared, mirror.releaseTimedHolds() { noteLocalChanges(after: 0) }
        publish(.synced(.now))
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
                resendEverything(syncEngine.state)
            }
        case .fetchedRecordZoneChanges(let changes):
            receive(changes.modifications.map(\.record), deletions: changes.deletions.map(\.recordID), state: syncEngine.state)
        case .sentRecordZoneChanges(let sent):
            if handleSent(SentChanges(sent), state: syncEngine.state) {
                Task { try? await syncEngine.fetchChanges() }
            }
        case .willSendChanges:
            sendStarted()
        case .willFetchChanges:
            publish(.syncing)
        case .didSendChanges:
            sendEnded()
        case .didFetchChanges:
            publish(.synced(.now))
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
    func record(for id: CKRecord.ID) -> CKRecord? {
        // A file new here has no entry yet: the scan that queued it put its name in the mirror's index.
        guard let path = mirror.path(forRecordName: id.recordName) else { return nil }
        let asAsset = path.hasPrefix("assets/")
        let staging = self.staging
        let read = mirror.outgoing(path) { size in
            size > Int64(Self.inlineLimit) || asAsset ? staging.appending(path: "\(id.recordName)-\(UUID().uuidString)") : nil
        }
        guard let file = read else { return nil }
        let record = mirror.systemFields(path).flatMap(Self.decodeSystemFields) ?? CKRecord(recordType: Self.recordType, recordID: id)
        record.encryptedValues["path"] = path
        if let staged = file.staged {
            record["file"] = CKAsset(fileURL: staged)
            record.encryptedValues["data"] = nil
        } else {
            record.encryptedValues["data"] = file.contents ?? Data()
            record["file"] = nil
        }
        // When the file last changed, encrypted like the rest (a plain field showed Apple when each file changed).
        record.encryptedValues["modifiedAt"] = file.modified
        var kept = file
        kept.contents = nil  // the hash says what went; the bytes aren't needed again
        lock.withLock { inflight[id.recordName] = kept }
        updateUploads { $0.sending(path, asOf: file.modified) }
        return record
    }

    /// Writes what arrived into the folder; returns the names of the records whose file now holds something the
    /// cloud doesn't (queued to go up again).
    @discardableResult
    func receive(_ records: [CKRecord], deletions: [CKRecord.ID], state: some CloudEngineState) -> Set<String> {
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
        if !push.isEmpty {
            state.add(pendingRecordZoneChanges: push.map { .saveRecord($0) })
            // Files merged or copied here (a conflicted page copy) are new files: they go up with the next scan.
            noteLocalChanges()
        }
        if touched {
            Log.info("cloud changes received", category: "cloud", context: ["records": "\(records.count + deletions.count)"])
            onReceived()
        }
        return Set(push.map(\.recordName))
    }

    /// Settles what a send did; returns whether a fetch should follow (a clash whose server record came without its
    /// asset).
    @discardableResult
    func handleSent(_ sent: SentChanges, state: some CloudEngineState) -> Bool {
        var refetch = false
        var zoneGone = false
        var storageWait: TimeInterval?
        let acknowledged = Date.now
        // Their staged copies go once the send is settled (another batch may still be sending its own).
        var settled: [CloudMirror.Outgoing] = []
        mirror.batch {
            for record in sent.saved {
                let flight = lock.withLock { inflight.removeValue(forKey: record.recordID.recordName) }
                if let flight { settled.append(flight) }
                guard let file = Self.sentFile(record, flight: flight) else { continue }
                mirror.saved(file, systemFields: Self.encodeSystemFields(record))
                updateUploads { $0.uploaded(file.path, asOf: file.modified, at: acknowledged) }
            }
            for id in sent.deleted {
                if let path = mirror.path(forRecordName: id.recordName) { mirror.deleted(path) }
            }
            // Already gone from the cloud (another device deleted it too): deleted all the same — or the delete
            // would be sent again at every scan.
            for failure in sent.failedDeletes where failure.error.code == .unknownItem {
                if let path = mirror.path(forRecordName: failure.id.recordName) { mirror.deleted(path) }
            }
        }
        if !sent.saved.isEmpty || !sent.deleted.isEmpty { lock.withLock { sendWentThrough = true } }
        for failure in sent.failedDeletes where failure.error.code != .unknownItem {
            Log.error("cloud delete failed: \(failure.error.code.rawValue)", category: "cloud")
        }
        for failure in sent.failedSaves {
            let id = failure.record.recordID
            let flight = lock.withLock { inflight.removeValue(forKey: id.recordName) }
            if let flight { settled.append(flight) }
            let path = failure.record.encryptedValues["path"] as? String ?? flight?.path
            switch Self.handling(of: failure.error.code) {
            case .clash:
                // Another device saved it first: settle with theirs; what the folder then holds goes up over it only
                // when it differs (`receive` queues it). The server's record in the error may come without its
                // asset: then nothing is resent on the old version (it would clash again) — a fetch brings the record
                // whole, and settling it queues the save.
                if let server = failure.error.serverRecord, Self.isReadable(server) {
                    let pushed = receive([server], deletions: [], state: state)
                    if let path {
                        if pushed.contains(id.recordName) {
                            updateUploads { $0.refused(path, retry: .queued) }
                        } else if let flight {
                            updateUploads { $0.uploaded(path, asOf: flight.modified, at: acknowledged) }
                        }
                    }
                } else {
                    refetch = true
                    if let path { updateUploads { $0.refused(path, retry: .queued) } }
                }
            case .zoneGone:
                zoneGone = true
                if let path { updateUploads { $0.refused(path, retry: .queued) } }
            case .recordGone:
                if let path { mirror.lostRecord(path) }
                state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                if let path { updateUploads { $0.refused(path, retry: .queued) } }
            case .sendAgain:
                state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                if let path { updateUploads { $0.refused(path, retry: .queued) } }
            case .engineRetries:
                if let path { updateUploads { $0.refused(path, retry: .retrying) } }
            case .storageFull:
                let wait = storageWait ?? nextQuotaWait()
                storageWait = wait
                if let flight { mirror.hold(flight, until: acknowledged.addingTimeInterval(wait)) }
                report(failure.error)
                if let path { updateUploads { $0.refused(path, retry: .failed) } }
            case .refused:
                if let flight { mirror.hold(flight, until: nil) }
                Log.error(
                    "cloud save failed: \(failure.error.code.rawValue)", category: "cloud",
                    context: ["kind": path.map(CloudMirror.kind(of:)) ?? "unknown"])
                report(failure.error)
                if let path { updateUploads { $0.refused(path, retry: .failed) } }
            }
        }
        if let storageWait {
            Log.warn("cloud storage full; files wait", category: "cloud", context: ["minutes": "\(Int(storageWait / 60))"])
        }
        // A save found the zone gone (deleted elsewhere): every file goes up again, as for a fetched zone deletion.
        if zoneGone {
            Log.warn("cloud zone not found on save", category: "cloud")
            resendEverything(state)
        }
        for flight in settled {
            if let staged = flight.staged { try? FileManager.default.removeItem(at: staged) }
        }
        return refetch
    }

    /// The wait for files refused for want of storage, doubling for the next refusal.
    private func nextQuotaWait() -> TimeInterval {
        lock.withLock {
            defer { quotaWait = min(quotaWait * 2, Self.quotaWaitLimit) }
            return quotaWait
        }
    }

    /// The zone is gone with everything in it: made again, and every file goes up.
    private func resendEverything(_ state: some CloudEngineState) {
        mirror.forgetCloud()
        state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        queueLocalChanges(into: state)
    }

    static func handling(of code: CKError.Code) -> SaveFailure {
        switch code {
        case .serverRecordChanged: .clash
        case .zoneNotFound, .userDeletedZone: .zoneGone
        case .unknownItem: .recordGone
        case .operationCancelled, .batchRequestFailed, .assetFileModified, .assetFileNotFound: .sendAgain
        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited, .notAuthenticated,
            .accountTemporarilyUnavailable:
            .engineRetries
        case .quotaExceeded: .storageFull
        default: .refused
        }
    }

    /// What the cloud took for a saved record: the file as read for this very record (the same inline bytes, or the
    /// same staged copy) — else what the record itself carries, unstamped, so the next scan reads the file again.
    static func sentFile(_ record: CKRecord, flight: CloudMirror.Outgoing?) -> CloudMirror.Outgoing? {
        guard let path = record.encryptedValues["path"] as? String else { return flight }
        let hash: String
        if let data = record.encryptedValues["data"] as? Data {
            hash = CloudMirror.hash(data)
        } else if let url = (record["file"] as? CKAsset)?.fileURL {
            if let flight, flight.staged == url { return flight }
            guard let fileHash = CloudMirror.hash(fileAt: url) else { return nil }
            hash = fileHash
        } else {
            return flight
        }
        if let flight, flight.path == path, flight.hash == hash { return flight }
        return CloudMirror.Outgoing(path: path, contents: nil, staged: nil, size: 0, modified: .distantPast, hash: hash)
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

extension CloudSync.SentChanges {
    init(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) {
        saved = sent.savedRecords
        failedSaves = sent.failedRecordSaves.map { (record: $0.record, error: $0.error) }
        deleted = sent.deletedRecordIDs
        failedDeletes = sent.failedRecordDeletes.map { (id: $0.key, error: $0.value) }
    }
}
