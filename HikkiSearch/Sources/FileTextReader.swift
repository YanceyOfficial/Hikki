import Foundation

/// Reads attached files' text into the index (`SearchIndex.setFileText`), one file at a time in the background.
/// One worker drains one queue, so a file asked for twice — by two pages, or by a reconcile and an autosave — is
/// read once; a file whose text is already kept, or that failed before, isn't read again. A file that isn't on
/// this device yet (iCloud) is left for a later pass (`SearchIndex.unreadFiles`).
public actor FileTextReader {
    /// What reading a file came to.
    public enum Outcome: Sendable, Equatable {
        case text(String)
        /// The file is here but holds nothing readable (damaged): kept as failed, not tried again.
        case unreadable
        /// Not on this device (yet).
        case missing
    }

    private let index: SearchIndex
    private let read: @Sendable (String) async -> Outcome
    private let onError: @Sendable (any Error) -> Void
    private let onRead: @Sendable (Int) -> Void
    private var pending: [String] = []
    /// Names queued or being read.
    private var queued = Set<String>()
    private var worker: Task<Void, Never>?

    /// `read` turns an asset name into its text (`AttachmentText`); `onError` hears of index reads and writes that
    /// failed, `onRead` how many files were read when the queue runs dry (for the log).
    public init(
        index: SearchIndex, read: @escaping @Sendable (String) async -> Outcome,
        onError: @escaping @Sendable (any Error) -> Void = { _ in }, onRead: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
        self.index = index
        self.read = read
        self.onError = onError
        self.onRead = onRead
    }

    /// Queues these files; the worker starts if it isn't running.
    public func enqueue(_ names: [String]) {
        for name in names where queued.insert(name).inserted { pending.append(name) }
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task(priority: .utility) { await self.drain() }
    }

    /// Returns once everything queued so far (and since) has been read.
    public func idle() async {
        while let worker { await worker.value }
    }

    private func drain() async {
        var count = 0
        while !pending.isEmpty {
            let name = pending.removeFirst()
            defer { queued.remove(name) }
            do {
                guard try !index.hasFileText(named: name) else { continue }
                switch await read(name) {
                case .text(let text):
                    try index.setFileText(text, named: name)
                    count += 1
                case .unreadable: try index.setFileText(nil, named: name)
                case .missing: break
                }
            } catch {
                onError(error)
            }
        }
        // No suspension between the empty check and this: a name enqueued meanwhile was drained above.
        worker = nil
        if count > 0 { onRead(count) }
    }
}
