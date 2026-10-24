import CryptoKit
import Foundation

/// The workspace folder as CloudKit carries it: every file in it (pages, history, comments, chats, assets, the
/// drawing library, workspace.json) is one record, named by its path. This side knows nothing of CloudKit — it says
/// which files changed here since the folder last agreed with the cloud, and writes what arrives from it, settling a
/// file both sides changed so nothing either wrote is lost (`resolve`). `CloudSync` moves the records.
///
/// Every file's last agreed state is kept (`Entry`: size, modification date, content hash and the record's system
/// fields), persisted next to the database — never in the folder, which it describes.
public final class CloudMirror: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var size: Int64
        public var modified: Date
        /// SHA-256 of the contents the cloud has.
        public var hash: String
        /// The record's system fields (its change tag) as last saved or fetched; nil before the first save.
        public var systemFields: Data?
    }

    struct State: Codable {
        var format = 1
        var entries: [String: Entry] = [:]
        /// `CKSyncEngine`'s own state, kept for it.
        var engine: Data?
        /// The iCloud account the workspace syncs with (its user record's name): the first one it met.
        var account: String?
        /// The account the workspace synced with until the user turned iCloud on again (`releaseAccount`): the next
        /// account met takes it, and if that is another one, nothing agreed with the old one's zone holds there.
        var releasedFrom: String?
    }

    public enum Change: Equatable, Hashable, Sendable {
        case save(String)
        case delete(String)

        public var path: String {
            switch self {
            case .save(let path), .delete(let path): path
            }
        }
    }

    /// A file as it goes up: its contents read once — in memory, or copied aside for an asset (`staged`) — so what the
    /// cloud gets is what `saved` records.
    public struct Outgoing: Sendable {
        public var path: String
        /// The contents, when they travel inside the record (nil when staged, or once no longer needed).
        public var contents: Data?
        /// The copy that goes up as the record's asset.
        public var staged: URL?
        public var size: Int64
        public var modified: Date
        public var hash: String
    }

    /// A file the cloud refused as it is now: for good (too large, not accepted) or until `until` (storage full).
    struct Hold {
        var size: Int64
        var modified: Date
        var until: Date?
    }

    public struct Options: Sendable {
        /// This device's name, for a conflicted copy's title.
        public var device: String?
        public var conflictTitle: ConflictCopy.Title

        public init(device: String? = nil, conflictTitle: @escaping ConflictCopy.Title = ConflictCopy.defaultTitle) {
            self.device = device
            self.conflictTitle = conflictTitle
        }
    }

    public let root: URL
    private let stateURL: URL
    private let options: Options
    private let lock = NSLock()
    private var state: State
    private var holding = 0
    private var dirty = false
    /// Every path met — agreed entries, files a scan listed, files that arrived — by its record's name, and back: a
    /// record's path is one lookup, never a hash of every known path or a walk of the folder (a first sync builds
    /// thousands of records). Under `lock`; never shrinks (a gone path's name still leads to it, harmlessly).
    private var pathsByName: [String: String] = [:]
    private var namesByPath: [String: String] = [:]
    /// How many record names were worked out (tests: once per path).
    private var namesComputed = 0
    /// Files the cloud refused (`hold`), by path: the scan leaves them out while they are as they were then — and,
    /// for a refusal that may pass (storage full), until its time — so they aren't read and sent again every ten
    /// seconds. In memory only: a relaunch tries each once more, and that is a fair time to. Under `lock`.
    private var holds: [String: Hold] = [:]

    public init(root: URL, stateURL: URL, options: Options = Options()) {
        self.root = root
        self.stateURL = stateURL
        self.options = options
        // Dates as plain numbers: a file's modification date has to come back exactly as it was read.
        if let data = try? Data(contentsOf: stateURL), let state = try? JSONDecoder().decode(State.self, from: data),
            state.format == 1
        {
            self.state = state
        } else {
            state = State()
        }
        for path in state.entries.keys { index(path) }
    }

    // MARK: - The record's name

    /// The record's name for a path: its hash, so names never show what the files are called (the path itself
    /// travels encrypted inside the record).
    public static func recordName(for path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The path a record name stands for, among the files this device knows (agreed with the cloud, or seen by the
    /// last scan of the folder).
    public func path(forRecordName name: String) -> String? {
        lock.withLock { pathsByName[name] }
    }

    /// How many record names were worked out so far (each path's once).
    var recordNamesComputed: Int { lock.withLock { namesComputed } }

    /// Adds a path to the record-name index; call under `lock` (or from `init`).
    private func index(_ path: String) {
        guard namesByPath[path] == nil else { return }
        let name = Self.recordName(for: path)
        namesComputed += 1
        namesByPath[path] = name
        pathsByName[name] = path
    }

    /// Only plain relative paths inside the folder sync: no `..`, no hidden files or iCloud placeholders.
    public static func isSyncable(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !parts.isEmpty else { return false }
        return parts.allSatisfy { part in !part.isEmpty && part != ".." && !part.hasPrefix(".") }
            && !path.hasSuffix(".icloud")
    }

    // MARK: - Engine state

    public var engineState: Data? { lock.withLock { state.engine } }

    public func setEngineState(_ data: Data?) {
        lock.withLock { state.engine = data }
        persist()
    }

    public func systemFields(_ path: String) -> Data? {
        lock.withLock { state.entries[path]?.systemFields }
    }

    /// The cloud lost what it had (its zone was deleted): nothing agreed with it holds any more. The files stay;
    /// every one goes up again — to the same account.
    public func forgetCloud() {
        lock.withLock {
            state = State(account: state.account)
            holds = [:]
        }
        persist()
    }

    // MARK: - Account

    /// Whether this iCloud account may sync the workspace: the first account it meets owns it, and no other one
    /// sends or receives a file of it — the pages here stay the owner's. An account taking over a workspace released
    /// by another one (`releaseAccount`) starts from nothing: its zone has none of the files, so every file goes up,
    /// and the engine's state — the old account's — is dropped before an engine is made from it.
    public func accountAllows(_ user: String) -> Bool {
        let (allowed, handedOver) = lock.withLock {
            var handedOver = false
            if state.account == nil {
                if let previous = state.releasedFrom, previous != user {
                    state.entries = [:]
                    state.engine = nil
                    holds = [:]
                    handedOver = true
                }
                state.account = user
                state.releasedFrom = nil
            }
            return (state.account == user, handedOver)
        }
        if handedOver { Log.info("cloud workspace handed to another account; everything goes up", category: "cloud") }
        persist()
        return allowed
    }

    /// The user turned iCloud on: the account the device uses now may take the workspace. The same account carries
    /// on where it was; another one gets everything (`accountAllows`).
    public func releaseAccount() {
        lock.withLock {
            if let account = state.account { state.releasedFrom = account }
            state.account = nil
        }
        persist()
    }

    // MARK: - Going up

    /// What changed in the folder since it last agreed with the cloud: files new or different (by size and date,
    /// then by contents), and files gone. A file the cloud refused as it still is (`hold`) is left out.
    public func localChanges(now: Date = .now) -> [Change] {
        let files = listFiles()
        // Only files whose size or date moved since they agreed are read — outside the lock, a large one takes a while.
        let suspects: [(path: String, url: URL)] = lock.withLock {
            files.compactMap { path, file in
                guard let entry = state.entries[path], entry.size != file.size || entry.modified != file.modified else {
                    return nil
                }
                return (path, file.url)
            }
        }
        var hashes: [String: String] = [:]
        for suspect in suspects {
            if let hash = Self.hash(fileAt: suspect.url) { hashes[suspect.path] = hash }
        }
        return lock.withLock {
            var changes: [Change] = []
            for (path, file) in files.sorted(by: { $0.key < $1.key }) {
                guard let entry = state.entries[path] else {
                    if !isHeld(path, file, now: now) { changes.append(.save(path)) }
                    continue
                }
                if entry.size == file.size, entry.modified == file.modified { continue }
                guard let hash = hashes[path] else { continue }
                if hash == entry.hash {
                    // Touched, not changed (an atomic rewrite of the same words): only the stamp moves.
                    state.entries[path]?.size = file.size
                    state.entries[path]?.modified = file.modified
                } else if !isHeld(path, file, now: now) {
                    changes.append(.save(path))
                }
            }
            for path in state.entries.keys.sorted() where files[path] == nil {
                changes.append(.delete(path))
            }
            return changes
        }
    }

    /// Whether the scan leaves the file out: refused as it still is, and — for a refusal that may pass — not yet
    /// time to try again. A hold the file outgrew goes. Call under `lock`.
    private func isHeld(_ path: String, _ file: FileInfo, now: Date) -> Bool {
        guard let hold = holds[path] else { return false }
        if hold.size == file.size, hold.modified == file.modified, hold.until.map({ now < $0 }) ?? true { return true }
        holds[path] = nil
        return false
    }

    /// The cloud refused `file` as it is: the scan leaves it out until it changes — or, with `until` (storage full),
    /// until then.
    public func hold(_ file: Outgoing, until: Date?) {
        lock.withLock { holds[file.path] = Hold(size: file.size, modified: file.modified, until: until) }
    }

    /// Files held for a while go now (storage was freed — a save went through — or the user asked to sync);
    /// returns whether there were any.
    @discardableResult
    public func releaseTimedHolds() -> Bool {
        lock.withLock {
            let before = holds.count
            holds = holds.filter { $0.value.until == nil }
            return holds.count != before
        }
    }

    /// The file as it is now, to go up; nil when it is gone (its deletion goes up instead). `stage` says, from its
    /// size, where to copy it when it goes as an asset (nil: its contents travel in the record): the copy is what is
    /// sent and hashed, read in chunks, so a large file is never held in memory whole.
    public func outgoing(_ path: String, stage: (Int64) -> URL? = { _ in nil }) -> Outgoing? {
        guard Self.isSyncable(path) else { return nil }
        let url = root.appending(path: path)
        guard let attributes = Self.attributes(of: url) else { return nil }
        if let copy = stage(attributes.size) {
            do {
                let manager = FileManager.default
                try manager.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
                if manager.fileExists(atPath: copy.path) { try manager.removeItem(at: copy) }
                try manager.copyItem(at: url, to: copy)
            } catch {
                Log.error("cloud asset staging failed: \(error)", category: "cloud", context: ["kind": Self.kind(of: path)])
                return nil
            }
            guard let hash = Self.hash(fileAt: copy) else { return nil }
            return Outgoing(
                path: path, contents: nil, staged: copy, size: attributes.size, modified: attributes.modified, hash: hash)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Outgoing(
            path: path, contents: data, staged: nil, size: attributes.size, modified: attributes.modified, hash: Self.hash(data))
    }

    /// The cloud took `file` as the record whose system fields are `systemFields`.
    public func saved(_ file: Outgoing, systemFields: Data?) {
        lock.withLock {
            state.entries[file.path] = Entry(size: file.size, modified: file.modified, hash: file.hash, systemFields: systemFields)
            index(file.path)
        }
        persist()
    }

    /// The cloud dropped the file's record.
    public func deleted(_ path: String) {
        lock.withLock { _ = state.entries.removeValue(forKey: path) }
        persist()
    }

    /// The record is gone from the cloud (deleted, or its zone reset): the file goes up as a new one.
    public func lostRecord(_ path: String) {
        lock.withLock { state.entries[path]?.systemFields = nil }
        persist()
    }

    // MARK: - Coming down

    /// What arriving from the cloud did here.
    public struct Received: Equatable, Sendable {
        /// Files written or removed in the folder (the workspace reconciles with them).
        public var touched: Bool
        /// The folder now holds something the cloud doesn't (a merge, or the local side won): it goes up again.
        public var needsPush: Bool
    }

    /// A record arrived (fetched, or the server's side of a save it refused): written over the file when this device
    /// hasn't changed it since they last agreed, otherwise settled with it (`resolve`).
    public func receive(_ path: String, contents: Data, systemFields: Data?) throws -> Received {
        guard Self.isSyncable(path) else { return Received(touched: false, needsPush: false) }
        let url = root.appending(path: path)
        // Held from reading the file to writing it: comments, chats and the drawing library write under the same lock
        // (`FileLocks`), so nothing of theirs lands between the two and is written over.
        return try FileLocks.shared.withLock(url) {
            try receive(path, url: url, contents: contents, systemFields: systemFields, attempts: 3)
        }
    }

    /// Runs just before an arriving file is written over the one read (tests: another writer getting in there).
    var beforeWrite: ((String) -> Void)?

    private func receive(_ path: String, url: URL, contents: Data, systemFields: Data?, attempts: Int) throws -> Received {
        let incomingHash = Self.hash(contents)
        let local = try? Data(contentsOf: url)
        let entry = lock.withLock { state.entries[path] }
        let localHash = local.map(Self.hash)
        // Still the file this was decided on? A writer outside the lock (another process, a file coordinator) may
        // have changed it since: then it is decided again with what it holds now — settled, not written over.
        let asRead = local
        func stillAsRead() -> Bool {
            beforeWrite?(path)
            guard attempts > 1 else { return true }
            return (try? Data(contentsOf: url)) == asRead
        }
        // Unchanged here since the last agreement (or never here): the cloud's version is the file.
        guard let local, let localHash, localHash != incomingHash, localHash != entry?.hash else {
            if localHash != incomingHash {
                guard stillAsRead() else {
                    return try receive(path, url: url, contents: contents, systemFields: systemFields, attempts: attempts - 1)
                }
                try write(contents, to: url)
            }
            record(path, url: url, hash: incomingHash, systemFields: systemFields)
            return Received(touched: localHash != incomingHash, needsPush: false)
        }
        // The cloud still holds what this device last agreed with it — an echo of this device's own save fetched
        // back, or a record fetched again — while the file has moved on (typing since): only this side changed.
        // Nothing to settle (settling made a conflicted copy of the page's own earlier words, or took the older
        // version back for files the cloud wins); the file stays and goes up on the record's current change tag.
        if let entry, incomingHash == entry.hash {
            lock.withLock { state.entries[path]?.systemFields = systemFields ?? entry.systemFields }
            persist()
            return Received(touched: false, needsPush: true)
        }
        // Both sides changed it.
        let settled = resolve(path, local: local, cloud: contents)
        if settled.file != local, !stillAsRead() {
            return try receive(path, url: url, contents: contents, systemFields: systemFields, attempts: attempts - 1)
        }
        for (extraPath, data) in settled.extra {
            try write(data, to: root.appending(path: extraPath))
        }
        if settled.file != local { try write(settled.file, to: url) }
        // Agreed with the cloud's version (its change tag); a file that differs from it keeps no stamp, so the next
        // scan reads it, sees it isn't the cloud's and sends it up over it.
        record(path, url: url, hash: incomingHash, systemFields: systemFields, stamped: settled.file == contents)
        Log.info(
            "cloud file changed on both sides; settled", category: "cloud",
            context: ["kind": Self.kind(of: path), "copies": "\(settled.extra.count)"])
        return Received(touched: true, needsPush: settled.file != contents || !settled.extra.isEmpty)
    }

    /// A record was deleted in the cloud: the file goes too, unless this device changed it since — then it stays
    /// and goes up again as a new record.
    public func receiveDeletion(_ path: String) throws -> Received {
        guard Self.isSyncable(path) else { return Received(touched: false, needsPush: false) }
        let url = root.appending(path: path)
        return try FileLocks.shared.withLock(url) { try receiveDeletion(path, url: url) }
    }

    private func receiveDeletion(_ path: String, url: URL) throws -> Received {
        let entry = lock.withLock { state.entries[path] }
        guard let local = try? Data(contentsOf: url) else {
            deleted(path)
            return Received(touched: false, needsPush: false)
        }
        if let entry, Self.hash(local) == entry.hash {
            try FileManager.default.removeItem(at: url)
            deleted(path)
            return Received(touched: true, needsPush: false)
        }
        lostRecord(path)
        return Received(touched: false, needsPush: true)
    }

    // MARK: - Settling a file both sides changed

    struct Settled {
        /// What the file holds now.
        var file: Data
        /// Files added beside it (a page's conflicted copy), by path.
        var extra: [(String, Data)] = []
    }

    /// Pages: the later change is the page, and the other — when it says something different — becomes a conflicted
    /// copy beside it, as for iCloud Drive's versions. Comments and chats: merged by id. Anything else (history
    /// versions and assets are written once; the drawing library and workspace.json): the cloud's version, the
    /// later write of two devices being as good a guess as any.
    func resolve(_ path: String, local: Data, cloud: Data) -> Settled {
        switch Self.kind(of: path) {
        case "page":
            guard let mine = try? PageFiles.decode(local), let theirs = try? PageFiles.decode(cloud) else {
                return Settled(file: cloud)
            }
            let localWins = mine.lastChange > theirs.lastChange
            let (winner, loser, winnerData) = localWins ? (mine, theirs, local) : (theirs, mine, cloud)
            guard ConflictCopy.differ(winner, loser) else { return Settled(file: winnerData) }
            // The cloud's side says nothing of where it was written.
            let source = ConflictCopy.source(device: localWins ? nil : options.device, date: loser.lastChange)
            let copy = ConflictCopy.make(from: loser, source: source, title: options.conflictTitle)
            guard let copyData = try? PageFiles.encoder.encode(copy) else { return Settled(file: winnerData) }
            return Settled(file: winnerData, extra: [("pages/\(copy.id).json", copyData)])
        case "comments":
            return Settled(file: PageComments.mergeFiles(local, cloud) ?? cloud)
        case "chat":
            return Settled(file: PageChats.mergeFiles(local, cloud) ?? cloud)
        default:
            return Settled(file: cloud)
        }
    }

    static func kind(of path: String) -> String {
        if path.hasPrefix("pages/") { return "page" }
        if path.hasPrefix("comments/") { return "comments" }
        if path.hasPrefix("ai/") { return "chat" }
        if path.hasPrefix("history/") { return "history" }
        if path.hasPrefix("assets/") { return "asset" }
        return "other"
    }

    // MARK: - Files

    struct FileInfo {
        var url: URL
        var size: Int64
        var modified: Date
    }

    /// Every syncable file in the folder, by path.
    func listFiles() -> [String: FileInfo] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [:] }
        let base = root.standardizedFileURL.path
        var files: [String: FileInfo] = [:]
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(base + "/") else { continue }
            let path = String(full.dropFirst(base.count + 1))
            guard Self.isSyncable(path) else { continue }
            files[path] = FileInfo(
                url: url, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast)
        }
        lock.withLock { for path in files.keys { index(path) } }
        return files
    }

    private func record(_ path: String, url: URL, hash: String, systemFields: Data?, stamped: Bool = true) {
        let attributes = stamped ? Self.attributes(of: url) : nil
        lock.withLock {
            state.entries[path] = Entry(
                size: attributes?.size ?? 0, modified: attributes?.modified ?? .distantPast, hash: hash,
                systemFields: systemFields)
            index(path)
        }
        persist()
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func attributes(of url: URL) -> (size: Int64, modified: Date)? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        return (Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The same hash of a file's contents, read a megabyte at a time; nil when it can't be read.
    static func hash(fileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Runs `body` saving the state once at its end, not after every file (a fetch brings thousands).
    public func batch<T>(_ body: () throws -> T) rethrows -> T {
        lock.withLock { holding += 1 }
        defer {
            let save = lock.withLock {
                holding -= 1
                return holding == 0 && dirty
            }
            if save { persist() }
        }
        return try body()
    }

    private func persist() {
        let data: Data? = lock.withLock {
            guard holding == 0 else {
                dirty = true
                return nil
            }
            dirty = false
            return try? JSONEncoder().encode(state)
        }
        guard let data else { return }
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            Log.warn("cloud state not saved: \(error)", category: "cloud")
        }
    }
}
