import CloudKit
import Foundation
import Testing

@testable import HikkiCore

/// `CKSyncEngine.State`'s pending changes, without CloudKit: what `CloudSync`'s handlers queue.
final class FakeEngineState: CloudEngineState {
    private(set) var records: [CKSyncEngine.PendingRecordZoneChange] = []
    private(set) var databaseChanges: [CKSyncEngine.PendingDatabaseChange] = []

    func add(pendingRecordZoneChanges changes: [CKSyncEngine.PendingRecordZoneChange]) {
        for change in changes where !records.contains(where: { Self.key($0) == Self.key(change) }) {
            records.append(change)
        }
    }

    func remove(pendingRecordZoneChanges changes: [CKSyncEngine.PendingRecordZoneChange]) {
        let keys = Set(changes.map(Self.key))
        records.removeAll { keys.contains(Self.key($0)) }
    }

    func add(pendingDatabaseChanges changes: [CKSyncEngine.PendingDatabaseChange]) {
        databaseChanges += changes
    }

    /// The record names with a save queued.
    var saves: Set<String> {
        Set(
            records.compactMap { change -> String? in
                guard case .saveRecord(let id) = change else { return nil }
                return id.recordName
            })
    }

    var deletes: Set<String> {
        Set(
            records.compactMap { change -> String? in
                guard case .deleteRecord(let id) = change else { return nil }
                return id.recordName
            })
    }

    var savesZone: Bool {
        databaseChanges.contains { change in
            guard case .saveZone(let zone) = change else { return false }
            return zone.zoneID == CloudSync.zoneID
        }
    }

    private static func key(_ change: CKSyncEngine.PendingRecordZoneChange) -> String {
        switch change {
        case .saveRecord(let id): "save \(id.recordName)"
        case .deleteRecord(let id): "delete \(id.recordName)"
        @unknown default: "other"
        }
    }
}

/// The statuses a `CloudSync` reported, in order.
final class StatusLog: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [CloudSync.Status] = []

    func append(_ status: CloudSync.Status) { lock.withLock { statuses.append(status) } }
    var last: CloudSync.Status? { lock.withLock { statuses.last } }
}

struct CloudSyncTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A `CloudSync` that never makes an engine: its handlers are called directly with a fake engine state.
    private func cloudSync(_ root: URL) throws -> (CloudSync, CloudMirror, StatusLog) {
        let mirror = CloudMirror(root: root, stateURL: try makeTempDirectory().appending(path: "cloud.json"))
        let log = StatusLog()
        let sync = CloudSync(mirror: mirror, onReceived: {}, onStatus: { log.append($0) })
        return (sync, mirror, log)
    }

    private func write(_ text: String, _ path: String, in root: URL) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Everything the scan sees goes up, and the cloud took it.
    private func pushAll(_ mirror: CloudMirror, systemFields: Data? = nil) {
        for change in mirror.localChanges() {
            if case .save(let path) = change, let file = mirror.outgoing(path) { mirror.saved(file, systemFields: systemFields) }
            if case .delete(let path) = change { mirror.deleted(path) }
        }
    }

    private func name(_ path: String) -> String { CloudMirror.recordName(for: path) }

    /// The record a send carried for `path`, built as the engine asks for it (so it is in flight).
    private func sentRecord(_ sync: CloudSync, _ mirror: CloudMirror, _ path: String) throws -> CKRecord {
        _ = mirror.localChanges()  // the scan that queued it, which names it
        return try #require(sync.record(for: CloudSync.recordID(for: path)))
    }

    private func serverRecord(_ path: String, _ text: String) -> CKRecord {
        let record = CKRecord(recordType: CloudSync.recordType, recordID: CloudSync.recordID(for: path))
        record.encryptedValues["path"] = path
        record.encryptedValues["data"] = Data(text.utf8)
        return record
    }

    private func clash(server: CKRecord?) -> CKError {
        CKError(.serverRecordChanged, userInfo: server.map { [CKRecordChangedErrorServerRecordKey: $0] } ?? [:])
    }

    /// A server record in a conflict may come without its asset: it isn't settled from (or resent over) then.
    @Test func aRecordWithoutItsContentsIsNotReadable() throws {
        let id = CloudSync.recordID(for: "pages/p.json")
        let inline = CKRecord(recordType: CloudSync.recordType, recordID: id)
        inline.encryptedValues["path"] = "pages/p.json"
        inline.encryptedValues["data"] = Data("{}".utf8)
        #expect(CloudSync.isReadable(inline))

        let missingAsset = CKRecord(recordType: CloudSync.recordType, recordID: id)
        missingAsset.encryptedValues["path"] = "assets/a.png"
        missingAsset["file"] = CKAsset(fileURL: try makeTempDirectory().appending(path: "not-downloaded"))
        #expect(!CloudSync.isReadable(missingAsset))

        let noPath = CKRecord(recordType: CloudSync.recordType, recordID: id)
        noPath.encryptedValues["data"] = Data("{}".utf8)
        #expect(!CloudSync.isReadable(noPath))
    }

    /// A clash whose server version is what the folder holds now (inline, or as an asset) settles to it: nothing is
    /// sent again, and the file is agreed.
    @Test func aClashSettledToTheServersVersionIsNotSentAgain() throws {
        let root = try makeTempDirectory()
        let (sync, mirror, _) = try cloudSync(root)
        try write("v1", "drawings/library.json", in: root)
        try write("p1", "assets/a.png", in: root)
        pushAll(mirror)
        try write("v2", "drawings/library.json", in: root)
        try write("p2", "assets/a.png", in: root)
        let library = try sentRecord(sync, mirror, "drawings/library.json")
        let asset = try sentRecord(sync, mirror, "assets/a.png")
        #expect(asset["file"] is CKAsset)

        let assetFile = try makeTempDirectory().appending(path: "downloaded")
        try Data("p2".utf8).write(to: assetFile)
        let serverAsset = CKRecord(recordType: CloudSync.recordType, recordID: CloudSync.recordID(for: "assets/a.png"))
        serverAsset.encryptedValues["path"] = "assets/a.png"
        serverAsset["file"] = CKAsset(fileURL: assetFile)

        let state = FakeEngineState()
        let refetch = sync.handleSent(
            .init(failedSaves: [
                (library, clash(server: serverRecord("drawings/library.json", "v2"))), (asset, clash(server: serverAsset)),
            ]),
            state: state)
        #expect(!refetch)
        #expect(state.saves.isEmpty)
        #expect(mirror.localChanges().isEmpty)
    }

    /// A clash both sides changed (comments added here and there) settles to a merge, which goes up over theirs.
    @Test func aClashBothSidesChangedSendsTheSettledFile() throws {
        let root = try makeTempDirectory()
        let there = try makeTempDirectory()
        let (sync, mirror, _) = try cloudSync(root)
        let mine = PageComments(root: root, author: "A", device: "Mac")
        try mine.create(pageId: "p", threadId: "t1", quote: "q", body: "first", now: t0)
        pushAll(mirror)
        try FileManager.default.createDirectory(at: there.appending(path: "comments"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appending(path: "comments/p.json"), to: there.appending(path: "comments/p.json"))
        try PageComments(root: there, author: "B", device: "iPhone")
            .create(pageId: "p", threadId: "t2", quote: "r", body: "theirs", now: t0.addingTimeInterval(5))
        try mine.create(pageId: "p", threadId: "t3", quote: "s", body: "mine", now: t0.addingTimeInterval(6))
        let sent = try sentRecord(sync, mirror, "comments/p.json")

        let server = CKRecord(recordType: CloudSync.recordType, recordID: sent.recordID)
        server.encryptedValues["path"] = "comments/p.json"
        server.encryptedValues["data"] = try Data(contentsOf: there.appending(path: "comments/p.json"))
        let state = FakeEngineState()
        sync.handleSent(.init(failedSaves: [(sent, clash(server: server))]), state: state)
        #expect(state.saves == [name("comments/p.json")])
        #expect(Set(try mine.threads(of: "p").map(\.id)) == ["t1", "t2", "t3"])
    }

    /// The server's record without its asset: nothing is sent on the old version; a fetch brings it whole.
    @Test func aClashWithoutTheAssetFetchesInstead() throws {
        let root = try makeTempDirectory()
        let (sync, mirror, _) = try cloudSync(root)
        try write("p1", "assets/a.png", in: root)
        let sent = try sentRecord(sync, mirror, "assets/a.png")
        let server = CKRecord(recordType: CloudSync.recordType, recordID: sent.recordID)
        server.encryptedValues["path"] = "assets/a.png"
        server["file"] = CKAsset(fileURL: try makeTempDirectory().appending(path: "not-downloaded"))
        let state = FakeEngineState()
        #expect(sync.handleSent(.init(failedSaves: [(sent, clash(server: server))]), state: state))
        #expect(state.saves.isEmpty)
    }

    /// A save finding the zone gone: the zone is made again and every file goes up, not only the one refused.
    @Test func aSaveFindingNoZoneSendsEverything() throws {
        let root = try makeTempDirectory()
        let (sync, mirror, _) = try cloudSync(root)
        try write("a", "pages/a.json", in: root)
        try write("b", "pages/b.json", in: root)
        pushAll(mirror, systemFields: Data([1]))
        try write("a2", "pages/a.json", in: root)
        let sent = try sentRecord(sync, mirror, "pages/a.json")
        let state = FakeEngineState()
        sync.handleSent(.init(failedSaves: [(sent, CKError(.zoneNotFound))]), state: state)
        #expect(state.savesZone)
        #expect(state.saves == [name("pages/a.json"), name("pages/b.json")])
        #expect(mirror.systemFields("pages/b.json") == nil)
    }

    @Test func aSaveOfAGoneRecordGoesUpAsANewOne() throws {
        let root = try makeTempDirectory()
        let (sync, mirror, _) = try cloudSync(root)
        try write("a", "pages/a.json", in: root)
        pushAll(mirror, systemFields: Data([1]))
        try write("a2", "pages/a.json", in: root)
        let sent = try sentRecord(sync, mirror, "pages/a.json")
        let state = FakeEngineState()
        sync.handleSent(.init(failedSaves: [(sent, CKError(.unknownItem))]), state: state)
        #expect(state.saves == [name("pages/a.json")])
        #expect(mirror.systemFields("pages/a.json") == nil)
    }

    /// Deleting a record another device deleted too: done all the same, not sent again at every scan.
    @Test func aDeleteOfAGoneRecordCountsAsDone() throws {
        let root = try makeTempDirectory()
        let (sync, mirror, _) = try cloudSync(root)
        try write("a", "pages/a.json", in: root)
        pushAll(mirror)
        try FileManager.default.removeItem(at: root.appending(path: "pages/a.json"))
        #expect(mirror.localChanges() == [.delete("pages/a.json")])
        sync.handleSent(
            .init(failedDeletes: [(CloudSync.recordID(for: "pages/a.json"), CKError(.unknownItem))]), state: FakeEngineState())
        #expect(mirror.localChanges().isEmpty)
    }

    /// Storage full: the status stays on through the end of the send, and the file isn't sent again at every scan
    /// until it changes (or its wait is over); a send that goes through clears it.
    @Test func storageFullStaysShownAndTheFileWaits() throws {
        let root = try makeTempDirectory()
        let (sync, mirror, log) = try cloudSync(root)
        try write("big", "assets/big.mov", in: root)
        sync.sendStarted()
        let sent = try sentRecord(sync, mirror, "assets/big.mov")
        sync.handleSent(.init(failedSaves: [(sent, CKError(.quotaExceeded))]), state: FakeEngineState())
        #expect(log.last == .quotaFull)
        sync.sendEnded()
        #expect(log.last == .quotaFull)
        sync.sendStarted()
        #expect(log.last == .quotaFull)

        let rescan = FakeEngineState()
        sync.queueLocalChanges(into: rescan)
        #expect(rescan.saves.isEmpty)

        // Another file goes through: the failure is cleared, and the waiting file is tried at once.
        try write("small", "pages/a.json", in: root)
        let small = try sentRecord(sync, mirror, "pages/a.json")
        sync.handleSent(.init(saved: [small]), state: FakeEngineState())
        sync.sendEnded()
        if case .synced? = log.last {} else { Issue.record("still \(String(describing: log.last))") }
        #expect(mirror.localChanges() == [.save("assets/big.mov")])

        // Refused again: it waits, and once its wait is over it goes again by itself.
        let again = try sentRecord(sync, mirror, "assets/big.mov")
        sync.handleSent(.init(failedSaves: [(again, CKError(.quotaExceeded))]), state: FakeEngineState())
        #expect(mirror.localChanges().isEmpty)
        #expect(mirror.localChanges(now: .now.addingTimeInterval(CloudSync.quotaWait + 1)) == [.save("assets/big.mov")])
    }

    /// A refusal for good (here: invalid arguments) is shown, and the file waits until it changes.
    @Test func aRefusedFileWaitsUntilItChanges() throws {
        let root = try makeTempDirectory()
        let (sync, mirror, log) = try cloudSync(root)
        try write("a", "pages/a.json", in: root)
        let sent = try sentRecord(sync, mirror, "pages/a.json")
        sync.handleSent(.init(failedSaves: [(sent, CKError(.invalidArguments))]), state: FakeEngineState())
        #expect(log.last == .failed("\(CKError.Code.invalidArguments.rawValue)"))
        #expect(mirror.localChanges().isEmpty)
        try write("a, edited", "pages/a.json", in: root)
        #expect(mirror.localChanges() == [.save("pages/a.json")])
    }

    /// A save the engine cancelled (or one that went down with its batch) is queued again.
    @Test func cancelledSavesAreSentAgain() throws {
        let root = try makeTempDirectory()
        let (sync, mirror, _) = try cloudSync(root)
        try write("a", "pages/a.json", in: root)
        try write("b", "pages/b.json", in: root)
        let a = try sentRecord(sync, mirror, "pages/a.json")
        let b = try sentRecord(sync, mirror, "pages/b.json")
        let state = FakeEngineState()
        sync.handleSent(
            .init(failedSaves: [(a, CKError(.operationCancelled)), (b, CKError(.batchRequestFailed))]), state: state)
        #expect(state.saves == [name("pages/a.json"), name("pages/b.json")])
    }

    /// A saved record is agreed as it was sent: the file goes no further until it changes; one that changed since it
    /// was read for the record goes up again.
    @Test func aSavedRecordIsAgreedAsSent() throws {
        let root = try makeTempDirectory()
        let (sync, mirror, _) = try cloudSync(root)
        try write("a", "pages/a.json", in: root)
        try write("b", "pages/b.json", in: root)
        let a = try sentRecord(sync, mirror, "pages/a.json")
        let b = try sentRecord(sync, mirror, "pages/b.json")
        try write("b, typed since", "pages/b.json", in: root)
        sync.handleSent(.init(saved: [a, b]), state: FakeEngineState())
        #expect(mirror.localChanges() == [.save("pages/b.json")])
        // A record saved without one in flight (built twice): agreed from what it carries.
        try write("b, typed since", "pages/b.json", in: root)
        sync.handleSent(.init(saved: [serverRecord("pages/b.json", "b, typed since")]), state: FakeEngineState())
        #expect(mirror.localChanges().isEmpty)
    }
}
