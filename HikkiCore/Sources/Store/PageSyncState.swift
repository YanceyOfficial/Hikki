import Foundation

/// How far a page's latest edit on this device has got, for the editor's quiet save indicator: typed, saved here,
/// on its way to iCloud, or in it. Worked out by `resolve` from what the editor reported, when the page was last
/// saved here and what `CloudUploads` knows of its file (`pages/<id>.json`). Never anything of the page's content.
public enum PageSyncState: Equatable, Sendable {
    /// Typed in the editor, not handed to the store yet (the editor's debounce).
    case saving
    /// Saved on this device, which is where the workspace stays (`Workspace.Location.device`, or a run that doesn't
    /// sync).
    case savedOnDevice(Date)
    /// Saved here, on its way to iCloud (waiting for the quiet second, queued, or being sent).
    case uploading
    /// Saved here; iCloud can't take it now (no network, or the network refused it): it goes up when it can.
    case waiting
    /// iCloud acknowledged the page as last saved here, at that moment.
    case synced(Date)
    /// Saved here, but iCloud isn't taking anything until the user acts.
    case notSyncing(Trouble)

    public enum Trouble: Equatable, Sendable {
        case noAccount
        case accountChanged
        case quotaFull
        case failed
        /// The user deleted the workspace's iCloud data: paused until they turn iCloud off and on.
        case cloudDataDeleted
    }

    /// iCloud as a whole, for one workspace.
    public enum Cloud: Equatable, Sendable {
        /// The workspace isn't kept in iCloud (or this run doesn't sync).
        case off
        case on
        case trouble(Trouble)
    }

    /// The page's state; nil when nothing was edited in it during this run (the indicator shows nothing then).
    public static func resolve(
        editing: Bool, savedAt: Date?, cloud: Cloud, upload: CloudUploads.Page?, offline: Bool
    ) -> PageSyncState? {
        if editing { return .saving }
        guard let savedAt else { return nil }
        switch cloud {
        case .off: return .savedOnDevice(savedAt)
        case .trouble(let trouble): return .notSyncing(trouble)
        case .on: break
        }
        switch upload?.phase {
        case .uploaded(let asOf, let at)? where asOf >= savedAt:
            return .synced(at)
        case .failed?:
            return .notSyncing(.failed)
        case .retrying?:
            return .waiting
        default:
            return offline ? .waiting : .uploading
        }
    }
}

/// Where the files of the pages edited in this run stand with iCloud, as `CloudSync` sees them go: saved here,
/// found changed by a scan and queued, sent, acknowledged — or refused. Only pages `saved(_:at:)` names are followed
/// (a handful per run), so a sync of thousands of files costs nothing here and changes nothing the indicator reads.
/// Each mutation returns whether anything changed, so nothing is published for nothing.
public struct CloudUploads: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Saved here; the next scan of the folder says whether its file differs from the cloud's.
        case pending
        /// In the engine's pending changes.
        case queued
        /// In a batch on its way, its file as modified at `asOf`.
        case sending(asOf: Date)
        /// The network refused it (offline, busy, rate limited): the engine tries again on its own.
        case retrying
        /// Refused for another reason (reported to the user with the status).
        case failed
        /// The cloud has the file as it was at `asOf` (its modification date, or a scan finding it unchanged then),
        /// acknowledged `at`.
        case uploaded(asOf: Date, at: Date)
    }

    public struct Page: Equatable, Sendable {
        /// Taken before the save's write: the page's file is at least this new once written.
        public var savedAt: Date
        /// Taken once the save's file was written: a scan that started earlier may have read the file before.
        public var writtenAt: Date
        public var phase: Phase
    }

    public private(set) var pages: [String: Page] = [:]
    /// No network path (`NWPathMonitor`): nothing goes up until there is one.
    public var offline = false
    /// Counts the published changes (`CloudSync` bumps it), so a reader hopping threads never takes an older copy
    /// over a newer one.
    public var revision = 0

    public init() {}

    /// The page id a workspace path stands for: `pages/<id>.json`; nil for any other file.
    public static func pageID(forPath path: String) -> String? {
        guard path.hasPrefix("pages/"), path.hasSuffix(".json") else { return nil }
        let id = path.dropFirst("pages/".count).dropLast(".json".count)
        guard !id.isEmpty, !id.contains("/") else { return nil }
        return String(id)
    }

    /// The editor saved the page at `at` and its file was written by `written`: followed from now on, waiting for
    /// the next scan. A file already in a batch stays there; its acknowledgement counts only if it is new enough.
    @discardableResult
    public mutating func saved(_ id: String, at: Date, written: Date) -> Bool {
        let old = pages[id]
        var phase = Phase.pending
        if let old, case .sending = old.phase { phase = old.phase }
        let page = Page(
            savedAt: max(at, old?.savedAt ?? at), writtenAt: max(written, old?.writtenAt ?? written), phase: phase)
        guard old != page else { return false }
        pages[id] = page
        return true
    }

    /// A scan of the folder that started at `at` found these paths changed since they last agreed with the cloud:
    /// those queued; every other followed page agrees with it — if the scan started after the page's file was
    /// written (an earlier one may have read the file before this save), and unless it is already known to.
    @discardableResult
    public mutating func scanned(changed paths: [String], at: Date) -> Bool {
        let changed = Set(paths.compactMap(Self.pageID(forPath:)))
        var updated = pages
        for (id, page) in pages {
            if case .sending = page.phase { continue }  // its acknowledgement says when
            if changed.contains(id) {
                updated[id]?.phase = .queued
            } else {
                if case .uploaded(let asOf, _) = page.phase, asOf >= page.savedAt { continue }
                guard at >= page.writtenAt else { continue }
                updated[id]?.phase = .uploaded(asOf: at, at: at)
            }
        }
        guard updated != pages else { return false }
        pages = updated
        return true
    }

    /// The file went into a batch, as modified at `asOf`.
    @discardableResult
    public mutating func sending(_ path: String, asOf: Date) -> Bool {
        set(path, .sending(asOf: asOf))
    }

    /// The cloud took the file as modified at `asOf`.
    @discardableResult
    public mutating func uploaded(_ path: String, asOf: Date, at: Date) -> Bool {
        set(path, .uploaded(asOf: asOf, at: at))
    }

    /// Sent again later: by the engine on its own (`retrying`), after settling a clash (`queued`), or not (`failed`).
    @discardableResult
    public mutating func refused(_ path: String, retry: Phase) -> Bool {
        set(path, retry)
    }

    /// Whether anything changed.
    @discardableResult
    public mutating func setOffline(_ value: Bool) -> Bool {
        guard offline != value else { return false }
        offline = value
        return true
    }

    private mutating func set(_ path: String, _ phase: Phase) -> Bool {
        guard let id = Self.pageID(forPath: path), let page = pages[id], page.phase != phase else { return false }
        pages[id]?.phase = phase
        return true
    }
}
