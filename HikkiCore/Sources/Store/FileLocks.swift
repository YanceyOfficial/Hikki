import Foundation

/// One lock per file of the workspace folder, shared by everything in the process that reads a file, decides and
/// writes it back: comments (`PageComments`), AI conversations (`PageChats`), the drawing library and what arrives
/// from iCloud (`CloudMirror.receive`). Without it a comment saved between iCloud reading the file and writing the
/// cloud's version over it was lost. Recursive, so a writer may read through its own helpers while holding it.
public final class FileLocks: @unchecked Sendable {
    public static let shared = FileLocks()

    private let lock = NSLock()
    /// The locks in use, by standardized path, with how many callers hold or wait for each (dropped at zero, so a
    /// sync of thousands of files keeps none of them).
    private var locks: [String: (lock: NSRecursiveLock, users: Int)] = [:]

    public init() {}

    /// Runs `body` holding the lock of the file at `url`.
    public func withLock<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
        let key = url.standardizedFileURL.path
        let fileLock: NSRecursiveLock = lock.withLock {
            var entry = locks[key] ?? (lock: NSRecursiveLock(), users: 0)
            entry.users += 1
            locks[key] = entry
            return entry.lock
        }
        fileLock.lock()
        defer {
            fileLock.unlock()
            lock.withLock {
                if let entry = locks[key] {
                    if entry.users <= 1 { locks[key] = nil } else { locks[key] = (lock: entry.lock, users: entry.users - 1) }
                }
            }
        }
        return try body()
    }
}
