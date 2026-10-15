import HikkiCore
import HikkiUI
import SwiftUI

/// Page ⋯ → Page History…: the page's kept versions (newest first) beside a preview of the one picked, marked
/// against the page as it is now; "Restore This Version" puts it back (the current page is kept as a version first).
struct PageHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    let pageID: String
    let restore: (PageVersion) async -> Void

    @State private var versions: [PageVersion] = []
    @State private var selection: PageVersion.ID?
    @State private var showsChanges = true
    @State private var loaded = false
    @State private var restoring = false
    /// The page as it is now, flattened once for every version's comparison.
    @State private var current: CurrentPage?

    var body: some View {
        NavigationStack {
            Group {
                if loaded && versions.isEmpty {
                    ContentUnavailableView {
                        IconLabel("app:history.empty", icon: .clockCounterClockwise)
                    } description: {
                        Text("app:history.emptyHint")
                    }
                } else if compact {
                    List(versions) { version in
                        NavigationLink(value: version.id) { VersionRow(version: version) }
                            .accessibilityIdentifier("history-version-\(index(of: version))")
                    }
                    .navigationDestination(for: PageVersion.ID.self) { id in
                        if let version = versions.first(where: { $0.id == id }) { detail(version) }
                    }
                } else {
                    HStack(spacing: Spacing.s0) {
                        List(versions, selection: $selection) { version in
                            VersionRow(version: version)
                                .tag(version.id)
                                .accessibilityIdentifier("history-version-\(index(of: version))")
                        }
                        .frame(width: Size.historyList)
                        Divider()
                        if let version = selected {
                            detail(version)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("app:history.title")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("app:common.close") { dismiss() }
                        .accessibilityIdentifier("history-close")
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: Size.historyWidth, minHeight: Size.historyHeight)
        #endif
        .task {
            // Every version file is read and decoded, and the page flattened, off the main thread.
            let record = try? model.store.document(id: pageID)
            async let loadedVersions = Self.load(model.history, pageID: pageID)
            async let now = Self.flatten(record)
            versions = await loadedVersions
            current = await now
            selection = versions.first?.id
            loaded = true
        }
    }

    private var compact: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    nonisolated struct CurrentPage: Sendable {
        let title: String
        let blocks: [TextBlock]
    }

    @concurrent nonisolated private static func load(_ history: PageHistory?, pageID: String) async -> [PageVersion] {
        guard let history else { return [] }
        do {
            return try history.versions(of: pageID)
        } catch {
            Log.error("page versions unreadable: \(error)", category: "history", context: ["docId": pageID])
            return []
        }
    }

    @concurrent nonisolated private static func flatten(_ record: DocumentRecord?) async -> CurrentPage? {
        guard let record else { return nil }
        return CurrentPage(title: record.title, blocks: TextBlock.blocks(in: try? record.contentValue()))
    }

    private var selected: PageVersion? {
        versions.first { $0.id == selection }
    }

    private func index(of version: PageVersion) -> Int {
        versions.firstIndex(of: version) ?? 0
    }

    private func detail(_ version: PageVersion) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s0) {
            HStack(spacing: Spacing.s3) {
                VStack(alignment: .leading, spacing: Spacing.s0_5) {
                    Text(version.savedAt.formatted(date: .complete, time: .shortened))
                        .font(.hk(.sm, .semibold))
                    VersionCaption(version: version)
                }
                Spacer(minLength: Spacing.s2)
                Toggle("app:history.showChanges", isOn: $showsChanges)
                    .toggleStyle(.switch)
                    .fixedSize()
                    .accessibilityIdentifier("history-show-changes")
                Button {
                    restoring = true
                    Task {
                        await restore(version)
                        restoring = false
                        dismiss()
                    }
                } label: {
                    IconLabel("app:history.restore", icon: .arrowCounterClockwise)
                }
                .buttonStyle(.borderedProminent)
                .disabled(restoring || model.tree.page(pageID)?.isLocked == true)
                .accessibilityIdentifier("history-restore")
            }
            .padding(Spacing.s4)
            if showsChanges {
                HStack(spacing: Spacing.s4) {
                    Legend(fill: Theme.washGreen, title: "app:history.legendVersion")
                    Legend(fill: Theme.washRed, title: "app:history.legendCurrent")
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.bottom, Spacing.s2)
            }
            Divider()
            VersionPreview(version: version, current: current, showsChanges: showsChanges)
                .accessibilityIdentifier("history-preview")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A version's title and body marked against the page now — what restoring would bring back, and what it would
/// remove. The comparison runs off the main thread, once per version shown (not on every redraw).
private struct VersionPreview: View {
    let version: PageVersion
    let current: PageHistoryView.CurrentPage?
    let showsChanges: Bool
    @State private var diff: Diff?

    nonisolated struct Diff: Sendable {
        let versionID: PageVersion.ID
        let title: [DiffRun]?
        let blocks: [BlockDiff]
    }

    var body: some View {
        ScrollView {
            if let diff, diff.versionID == version.id {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    VersionTitleView(
                        title: version.title, runs: diff.title?.map { VersionDiffView.Run($0.text, Self.change($0.change)) },
                        placeholder: String(localized: "app:page.untitled"), showsChanges: showsChanges)
                    VersionDiffView(blocks: Self.blocks(diff.blocks), showsChanges: showsChanges)
                }
                .padding(Spacing.s6)
                .frame(maxWidth: Size.column, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .task(id: version.id) {
            diff = await Self.compare(version, with: current)
        }
    }

    @concurrent nonisolated private static func compare(_ version: PageVersion, with current: PageHistoryView.CurrentPage?) async
        -> Diff
    {
        Diff(
            versionID: version.id,
            title: current.flatMap { PageDiff.title(old: $0.title, new: version.title) },
            blocks: PageDiff.compare(old: current?.blocks ?? [], new: TextBlock.blocks(in: version.content)))
    }

    private static func blocks(_ diff: [BlockDiff]) -> [VersionDiffView.Block] {
        diff.enumerated().map { index, entry in
            VersionDiffView.Block(
                id: index, style: style(entry.block.kind), depth: entry.block.depth,
                change: entry.status == .added ? .added : entry.status == .removed ? .removed : .same,
                runs: entry.runs.map { VersionDiffView.Run($0.text, change($0.change)) })
        }
    }

    private static func change(_ change: DiffChange) -> VersionDiffView.Change {
        switch change {
        case .same: .same
        case .added: .added
        case .removed: .removed
        }
    }

    private static func style(_ kind: TextBlock.Kind) -> VersionDiffView.Style {
        switch kind {
        case .paragraph, .math: .paragraph
        case .heading1: .heading1
        case .heading2: .heading2
        case .heading3: .heading3
        case .bullet: .bullet
        case .numbered: .numbered
        case .task: .task
        case .taskDone: .taskDone
        case .quote: .quote
        case .code: .code
        case .table: .table
        case .media: .media
        case .rule: .rule
        }
    }
}

/// One kept version in the list: when (relative), and where and why.
private struct VersionRow: View {
    let version: PageVersion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s0_5) {
            Text(version.savedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.hk(.sm, .medium))
            Text(version.savedAt, format: .relative(presentation: .named))
                .font(.hk(.xs))
                .foregroundStyle(.secondary)
            VersionCaption(version: version)
        }
        .padding(.vertical, Spacing.s1)
    }
}

/// The device a version was kept on, and why (before a restore, from another device).
private struct VersionCaption: View {
    let version: PageVersion

    var body: some View {
        HStack(spacing: Spacing.s1) {
            if let device = version.device {
                Text(verbatim: device)  // the device's own name
            }
            switch version.reason {
            case .edit: EmptyView()
            case .restore: Text("app:history.reasonRestore")
            case .sync: Text("app:history.reasonSync")
            }
        }
        .font(.hk(.xs))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct Legend: View {
    let fill: Color
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: Spacing.s1) {
            RoundedRectangle(cornerRadius: Radius.sm).fill(fill).frame(width: Spacing.s3, height: Spacing.s3)
            Text(title).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
        }
    }
}
