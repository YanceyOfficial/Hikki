import Foundation

/// Another version of a file that iCloud kept because two devices changed it at once.
public struct FileConflictVersion: Sendable {
    /// The version's contents (nil when they can't be read).
    public var contents: Data?
    /// When it was saved, and on which device (its user-visible name), when known.
    public var modified: Date?
    public var device: String?

    public init(contents: Data?, modified: Date?, device: String?) {
        self.contents = contents
        self.modified = modified
        self.device = device
    }
}

/// Unresolved conflict versions of a file, and resolving them — `NSFileVersion` in the app, a fake in tests.
public protocol FileVersionStore: Sendable {
    /// The other versions of the file at `url` iCloud hasn't had resolved yet (empty when there are none).
    func conflicts(at url: URL) -> [FileConflictVersion]
    /// The device that saved the current version of the file, when known.
    func currentDevice(at url: URL) -> String?
    /// Marks every conflict of the file resolved and lets iCloud drop the other versions.
    func resolveConflicts(at url: URL) throws
}

/// iCloud's conflict versions (`NSFileVersion`). Files outside iCloud never have any.
public struct UbiquitousFileVersions: FileVersionStore {
    public init() {}

    public func conflicts(at url: URL) -> [FileConflictVersion] {
        // The resource value is cheap; the version list is only read for a file that has conflicts.
        var url = url
        url.removeAllCachedResourceValues()
        guard (try? url.resourceValues(forKeys: [.ubiquitousItemHasUnresolvedConflictsKey]))?.ubiquitousItemHasUnresolvedConflicts == true,
            let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url)
        else { return [] }
        return versions.map { version in
            FileConflictVersion(
                contents: try? Data(contentsOf: version.url), modified: version.modificationDate,
                device: version.localizedNameOfSavingComputer)
        }
    }

    public func currentDevice(at url: URL) -> String? {
        NSFileVersion.currentVersionOfItem(at: url)?.localizedNameOfSavingComputer
    }

    public func resolveConflicts(at url: URL) throws {
        var failure: (any Error)?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) {
            target in
            do {
                for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: target) ?? [] { version.isResolved = true }
                try NSFileVersion.removeOtherVersionsOfItem(at: target)
            } catch {
                failure = error
            }
        }
        if let error = coordinationError ?? failure { throw error }
    }
}

/// Turning the losing side of a conflict into a page of its own: nothing either device wrote is lost.
public enum ConflictCopy {
    /// "<title> (conflicted copy <device>, <date>)" — the app passes a localized one.
    public typealias Title = @Sendable (_ title: String, _ source: String) -> String

    public static let defaultTitle: Title = { title, source in "\(title) (conflicted copy \(source))" }

    /// Where the losing version came from, for its title: the device and the date, or the date alone.
    public static func source(device: String?, date: Date) -> String {
        let when = date.formatted(date: .abbreviated, time: .shortened)
        guard let device, !device.isEmpty else { return when }
        return "\(device), \(when)"
    }

    /// A sibling page holding `loser`: a new id, its title marked, placed right after the page it came from. Not
    /// favorited or locked (the original keeps those).
    public static func make(from loser: PageFile, id: String = UUID().uuidString, source: String, title: Title) -> PageFile {
        var copy = loser
        copy.id = id
        copy.title = title(loser.title, source)
        copy.sortKey = loser.sortKey + 0.5
        copy.favoritedAt = nil
        copy.lockedAt = nil
        return copy
    }

    /// Whether two versions say different things (title or body) — metadata alone isn't worth a copy.
    public static func differ(_ a: PageFile, _ b: PageFile) -> Bool {
        a.title != b.title || a.content != b.content
    }
}
