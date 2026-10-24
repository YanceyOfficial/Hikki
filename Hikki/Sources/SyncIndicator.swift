import Foundation
import HikkiCore
import HikkiUI
import Observation
import SwiftUI

/// Where each page's latest edit in this run has got to, for the editor's save indicator (`SyncIndicator`): the
/// editor typing (`editing` from the page) and saving (`pageSavedInEditor`), and iCloud taking the page's file
/// (`CloudSync`'s `CloudUploads`). One for the app (`AppModel.pageSync`). Only the indicator reads it, so a save
/// redraws that chip and nothing else — not the editor, the sidebar or the window.
@Observable
final class PageSyncTracker {
    /// Pages typed in since their last save.
    private(set) var editing: Set<String> = []
    /// When each page was last saved here, in this run.
    private(set) var savedAt: [String: Date] = [:]
    private(set) var uploads = CloudUploads()
    /// iCloud for the workspace: off (kept on this device, or a run that doesn't sync), on, or in trouble.
    private(set) var cloud: PageSyncState.Cloud = .off
    /// A page was saved here (AppModel: its file is followed up to iCloud, `CloudSync.noteSaved`).
    @ObservationIgnored var onSaved: ((String, Date) -> Void)?
    /// For the app's life (the tracker is the app model's).
    @ObservationIgnored private var tokens: [any NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        tokens = [
            center.addObserver(forName: .pageEditingInEditor, object: nil, queue: .main) { [weak self] note in
                guard let id = note.userInfo?["id"] as? String else { return }
                MainActor.assumeIsolated { self?.edited(id) }
            },
            center.addObserver(forName: .pageSavedInEditor, object: nil, queue: .main) { [weak self] note in
                guard let id = note.userInfo?["id"] as? String else { return }
                let at = note.userInfo?["at"] as? Date ?? .now
                MainActor.assumeIsolated { self?.saved(id, at: at) }
            },
            // The save failed (its toast says so): no "Saving…" left hanging — the page shows its last saved state.
            center.addObserver(forName: .pageSaveFailedInEditor, object: nil, queue: .main) { [weak self] note in
                guard let id = note.userInfo?["id"] as? String else { return }
                MainActor.assumeIsolated { self?.saveFailed(id) }
            },
        ]
    }

    /// iCloud for the workspace changed; assigned only when it did (the status changes with every sync).
    func setCloud(_ value: PageSyncState.Cloud) {
        if cloud != value { cloud = value }
    }

    private func edited(_ id: String) {
        if !editing.contains(id) { editing.insert(id) }
    }

    private func saveFailed(_ id: String) {
        if editing.contains(id) { editing.remove(id) }
    }

    private func saved(_ id: String, at: Date) {
        if editing.contains(id) { editing.remove(id) }
        savedAt[id] = max(at, savedAt[id] ?? at)
        onSaved?(id, at)
    }

    /// Which `CloudSync` the uploads come from (`resetUploads`).
    @ObservationIgnored private var generation = 0

    /// The cloud's latest view of the followed pages; an older copy arriving late, or one from a `CloudSync` that
    /// was replaced since, is dropped.
    func apply(_ new: CloudUploads, generation: Int) {
        guard generation == self.generation, new.revision > uploads.revision else { return }
        uploads = new
    }

    /// A new `CloudSync` (iCloud turned on or off, the workspace restarted) counts from nothing; returns the
    /// generation its uploads are applied under.
    func resetUploads() -> Int {
        generation += 1
        uploads = CloudUploads()
        return generation
    }

    /// The page's state; nil when nothing was edited in it during this run.
    func state(of pageID: String) -> PageSyncState? {
        PageSyncState.resolve(
            editing: editing.contains(pageID), savedAt: savedAt[pageID], cloud: cloud, upload: uploads.pages[pageID],
            offline: uploads.offline)
    }
}

/// The save indicator in the bottom-trailing corner of a page (Mac and iPad: `PaneColumn`; the iPhone's foot belongs
/// to its floating bar, so it has none): nothing until the page is edited in this run, then "Saving…", "Saved" (a
/// workspace on this device), "Syncing…", "Synced to iCloud", "Waiting to sync" or "Not syncing". A settled state
/// keeps only its glyph after a few quiet seconds; the tooltip gives the time of the last save or sync.
struct SyncIndicator: View {
    let pageID: String
    let tracker: PageSyncTracker
    /// The words faded out (a settled state, a while after it changed).
    @State private var compact = false

    /// How long a settled state keeps its words.
    private static let settle: Duration = .seconds(4)

    var body: some View {
        let state = tracker.state(of: pageID)
        ZStack {
            if let state {
                let look = Self.look(state)
                SyncStatusBadge(kind: look.kind, title: look.title, detail: look.detail, compact: compact)
                    .transition(.opacity)
            }
        }
        .animation(Motion.easeOut(), value: state)
        .task(id: state) {
            compact = false
            guard let state, Self.settles(state) else { return }
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.easeOut()) { compact = true }
        }
    }

    /// Saved and synced settle; work in progress and anything waiting keep their words.
    private static func settles(_ state: PageSyncState) -> Bool {
        switch state {
        case .savedOnDevice, .synced: true
        case .saving, .uploading, .waiting, .notSyncing: false
        }
    }

    private static func look(_ state: PageSyncState) -> (kind: SyncStatusBadge.Kind, title: String, detail: String) {
        switch state {
        case .saving:
            let title = String(localized: "app:saveStatus.saving")
            return (.saving, title, title)
        case .savedOnDevice(let at):
            return (
                .saved, String(localized: "app:saveStatus.saved"),
                String(localized: "app:saveStatus.savedAt \(at.formatted(date: .omitted, time: .shortened))")
            )
        case .uploading:
            return (.uploading, String(localized: "app:saveStatus.uploading"), String(localized: "app:saveStatus.uploadingDetail"))
        case .waiting:
            return (.waiting, String(localized: "app:saveStatus.waiting"), String(localized: "app:saveStatus.waitingDetail"))
        case .synced(let at):
            return (
                .synced, String(localized: "app:saveStatus.synced"),
                String(localized: "app:saveStatus.syncedAt \(at.formatted(date: .omitted, time: .shortened))")
            )
        case .notSyncing(let trouble):
            let detail =
                switch trouble {
                case .noAccount: String(localized: "app:cloud.noAccount")
                case .accountChanged: String(localized: "app:cloud.accountChanged")
                case .quotaFull: String(localized: "app:cloud.quotaFull")
                case .failed: String(localized: "app:saveStatus.refused")
                case .cloudDataDeleted: String(localized: "app:cloud.dataDeleted")
                }
            return (.trouble, String(localized: "app:saveStatus.notSyncing"), detail)
        }
    }
}
