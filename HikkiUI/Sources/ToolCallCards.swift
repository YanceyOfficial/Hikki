import SwiftUI

/// A workspace file tool an AI answer used, as its card shows it (actovia's file cards): what it did, on which file or
/// folder, how it went, and what it read, wrote or changed. Plain values; the app says what the summary reads.
public struct ToolCallCardItem: Identifiable, Equatable {
    public enum Kind: Sendable, Equatable {
        case list, read, find, search, write, edit
    }

    public enum State: Equatable {
        case running
        /// A write or edit waiting for the user to allow it.
        case waiting
        case done
        /// Why, in the tool's words.
        case failed(String)
        case declined
        case stopped
    }

    /// A line of an edit's or a write's diff.
    public struct DiffLine: Equatable {
        public enum Sign: Equatable { case context, added, removed }

        public var sign: Sign
        public var text: String
        /// Unchanged lines left out here (the line's text is then unused).
        public var gap: Int?

        public init(_ sign: Sign, _ text: String, gap: Int? = nil) {
            self.sign = sign
            self.text = text
            self.gap = gap
        }
    }

    public var id: String
    public var kind: Kind
    /// The file or folder, relative to the workspace folder ("" for its top).
    public var path: String
    /// What a find or search looked for.
    public var pattern: String?
    public var state: State
    /// "12 lines", "3 matches", "New file" — the app's words.
    public var summary: String?
    /// What was read or written, or the paths found.
    public var lines: [String]
    /// An edit's change (lines kept around it folded away); nil when there is no diff to show.
    public var diff: [DiffLine]?
    public var added: Int
    public var removed: Int

    public init(
        id: String, kind: Kind, path: String, pattern: String? = nil, state: State, summary: String? = nil,
        lines: [String] = [], diff: [DiffLine]? = nil, added: Int = 0, removed: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.pattern = pattern
        self.state = state
        self.summary = summary
        self.lines = lines
        self.diff = diff
        self.added = added
        self.removed = removed
    }
}

/// The file tools an answer used, a card each, in order. A write or edit waiting for the user asks: Allow / Don't
/// Allow. Read and written text shows a few lines, an edit its diff (open while an answer has one or two), each with
/// Show all.
public struct ToolCallCards: View {
    let items: [ToolCallCardItem]
    let onAllow: (String) -> Void
    let onDecline: (String) -> Void

    public init(items: [ToolCallCardItem], onAllow: @escaping (String) -> Void, onDecline: @escaping (String) -> Void) {
        self.items = items
        self.onAllow = onAllow
        self.onDecline = onDecline
    }

    /// From three edits on, the answer is a refactor: its diffs start folded to their counts.
    private var diffsStartOpen: Bool { items.count { $0.kind == .edit } < 3 }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            ForEach(items) { item in
                ToolCallCard(
                    item: item, diffStartsOpen: diffsStartOpen || item.state == .waiting, onAllow: { onAllow(item.id) },
                    onDecline: { onDecline(item.id) })
            }
        }
        .animation(Motion.easeOut(), value: items)
    }
}

struct ToolCallCard: View {
    let item: ToolCallCardItem
    let diffStartsOpen: Bool
    let onAllow: () -> Void
    let onDecline: () -> Void
    @State private var expanded = false
    @State private var diffOpen: Bool?
    @Environment(\.colorTone) private var tone

    /// Lines shown before Show all.
    private static let previewLines = 6
    private static let previewResults = 5

    private var isDiffOpen: Bool { diffOpen ?? diffStartsOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s0) {
            header
            content
            if item.state == .waiting { approval }
        }
        .background(Theme.card, in: .rect(cornerRadius: Radius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(item.state == .waiting ? tone.fill : Theme.border, lineWidth: Spacing.px)
        }
        .clipShape(.rect(cornerRadius: Radius.xl))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-tool-card")
    }

    // MARK: - Header

    private var header: some View {
        let band = HStack(alignment: .center, spacing: Spacing.s2_5) {
            IconView(item.kind.icon, size: TextSize.sm.rawValue)
                .foregroundStyle(Theme.mutedForeground)
            VStack(alignment: .leading, spacing: Spacing.px) {
                Text(verbatim: title)
                    .font(.hk(.sm, .medium))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: Spacing.s0) {
                    Text(item.kind.label)
                    if let place { Text(verbatim: " · \(place)") }
                }
                .font(.hk(.xs))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
                .truncationMode(.head)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2_5)
        .contentShape(.rect)
        return Group {
            if item.diff != nil, item.state != .waiting {
                Button {
                    withAnimation(Motion.easeOut()) { diffOpen = !isDiffOpen }
                } label: {
                    band
                }
                .buttonStyle(.plain)
                .accessibilityValue(Text(isDiffOpen ? "app:ai.tools.expanded" : "app:ai.tools.collapsed"))
            } else {
                band
            }
        }
    }

    /// The file's name, the pattern looked for, or the folder listed.
    private var title: String {
        switch item.kind {
        case .find, .search: "“\(item.pattern ?? "")”"
        default:
            item.path.isEmpty ? String(localized: "app:ai.tools.workspace") : (item.path as NSString).lastPathComponent
        }
    }

    /// Where: the file's folder, or the folder a find or search looked in.
    private var place: String? {
        let folder = item.kind == .find || item.kind == .search ? item.path : (item.path as NSString).deletingLastPathComponent
        return folder.isEmpty ? nil : folder
    }

    @ViewBuilder private var trailing: some View {
        switch item.state {
        case .running:
            ProgressView().controlSize(.small)
        case .failed:
            IconView(.warningCircle, size: TextSize.sm.rawValue).foregroundStyle(Theme.destructive)
        case .declined:
            Text("app:ai.tools.declined").font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
        case .stopped:
            Text("app:ai.tools.stopped").font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
        case .waiting, .done:
            HStack(spacing: Spacing.s1_5) {
                if item.diff != nil {
                    DiffCount(added: item.added, removed: item.removed)
                } else if let summary = item.summary {
                    Text(verbatim: summary).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground).fixedSize()
                }
                if item.diff != nil, item.state != .waiting {
                    IconView(.caretRight, size: TextSize.xs.rawValue)
                        .foregroundStyle(Theme.subtleForeground)
                        .rotationEffect(.degrees(isDiffOpen ? 90 : 0))
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if case .failed(let message) = item.state {
            Divider().overlay(Theme.border)
            Text(verbatim: message)
                .font(.hk(.xs, design: .monospaced))
                .foregroundStyle(Theme.destructive)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s2)
        } else if let diff = item.diff {
            if isDiffOpen, !diff.isEmpty {
                Divider().overlay(Theme.border)
                diffLines(diff)
            }
        } else if !item.lines.isEmpty {
            Divider().overlay(Theme.border)
            if item.kind == .find || item.kind == .search || item.kind == .list {
                results
            } else {
                textLines
            }
        }
    }

    private var textLines: some View {
        let long = item.lines.count > Self.previewLines + 2
        let shown = expanded || !long ? item.lines : Array(item.lines.prefix(Self.previewLines))
        return VStack(alignment: .leading, spacing: Spacing.s0) {
            VStack(alignment: .leading, spacing: Spacing.px) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s2_5) {
                        Text(verbatim: "\(index + 1)")
                            .foregroundStyle(Theme.subtleForeground)
                            .frame(minWidth: Spacing.s5, alignment: .trailing)
                            .accessibilityHidden(true)
                        Text(verbatim: line.isEmpty ? " " : line)
                            .foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .font(.hk(.xs, design: .monospaced))
            .textSelection(.enabled)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            if long { expandRow(total: item.lines.count) }
        }
    }

    private var results: some View {
        let long = item.lines.count > Self.previewResults + 1
        let shown = expanded || !long ? item.lines : Array(item.lines.prefix(Self.previewResults))
        return VStack(alignment: .leading, spacing: Spacing.s0) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, path in
                    Text(verbatim: path)
                        .font(.hk(.xs, design: .monospaced))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            if long { expandRow(total: item.lines.count) }
        }
    }

    private func diffLines(_ diff: [ToolCallCardItem.DiffLine]) -> some View {
        let cap = 120
        let shown = expanded || diff.count <= cap ? diff : Array(diff.prefix(cap))
        return VStack(alignment: .leading, spacing: Spacing.s0) {
            VStack(alignment: .leading, spacing: Spacing.s0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                    if let gap = line.gap {
                        Text("app:ai.tools.unchanged \(String(gap))")
                            .font(.hk(.xs))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.s7)
                            .padding(.vertical, Spacing.px)
                            .background(Theme.muted)
                    } else {
                        diffLine(line)
                    }
                }
            }
            .font(.hk(.xs, design: .monospaced))
            .textSelection(.enabled)
            .padding(.vertical, Spacing.s1_5)
            if diff.count > cap { expandRow(total: diff.count) }
        }
    }

    private func diffLine(_ line: ToolCallCardItem.DiffLine) -> some View {
        let (sign, ink, wash): (String, Color, Color) =
            switch line.sign {
            case .context: (" ", Theme.subtleForeground, .clear)
            case .added: ("+", Theme.inkGreen, Theme.washGreen)
            case .removed: ("−", Theme.inkRed, Theme.washRed)
            }
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Text(verbatim: sign).foregroundStyle(ink).frame(width: Spacing.s2_5)
            Text(verbatim: line.text.isEmpty ? " " : line.text)
                .foregroundStyle(Theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.s2_5)
        .padding(.vertical, Spacing.px)
        .background(wash)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(line))
    }

    private func spoken(_ line: ToolCallCardItem.DiffLine) -> Text {
        switch line.sign {
        case .added: Text("app:ai.tools.addedLine \(line.text)")
        case .removed: Text("app:ai.tools.removedLine \(line.text)")
        case .context: Text(verbatim: line.text)
        }
    }

    private func expandRow(total: Int) -> some View {
        VStack(spacing: Spacing.s0) {
            Divider().overlay(Theme.border)
            Button {
                withAnimation(Motion.easeOut()) { expanded.toggle() }
            } label: {
                HStack(spacing: Spacing.s1_5) {
                    IconView(.caretDown, size: TextSize.xs.rawValue).rotationEffect(.degrees(expanded ? 180 : 0))
                    Text(expanded ? "app:ai.tools.showLess" : "app:ai.tools.showAll \(String(total))")
                }
                .font(.hk(.xs, .medium))
                .foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity, minHeight: Size.iconButton)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ai-tool-show-all")
        }
    }

    // MARK: - Asking

    private var approval: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(item.kind == .edit ? "app:ai.tools.askEdit" : "app:ai.tools.askWrite")
                .font(.hk(.xs))
                .foregroundStyle(Theme.mutedForeground)
            HStack(spacing: Spacing.s2) {
                Button("app:ai.tools.decline", action: onDecline)
                    .buttonStyle(.hikki(.outline))
                    .accessibilityIdentifier("ai-tool-decline")
                Button("app:ai.tools.allow", action: onAllow)
                    .buttonStyle(.hikki(.primary))
                    .accessibilityIdentifier("ai-tool-allow")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s3)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }
}

/// An edit's +N −M.
struct DiffCount: View {
    let added: Int
    let removed: Int

    var body: some View {
        HStack(spacing: Spacing.s1_5) {
            Text(verbatim: "+\(added)").foregroundStyle(Theme.inkGreen)
            Text(verbatim: "−\(removed)").foregroundStyle(Theme.inkRed)
        }
        .font(.hk(.xs, .medium))
        .monospacedDigit()
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("app:ai.tools.diffCount \(String(added)) \(String(removed))"))
    }
}

extension ToolCallCardItem.Kind {
    var icon: Icon {
        switch self {
        case .list: .folderSimple
        case .read: .fileText
        case .find: .magnifyingGlass
        case .search: .listMagnifyingGlass
        case .write: .notePencil
        case .edit: .pencilSimple
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .list: "app:ai.tools.list"
        case .read: "app:ai.tools.read"
        case .find: "app:ai.tools.find"
        case .search: "app:ai.tools.search"
        case .write: "app:ai.tools.write"
        case .edit: "app:ai.tools.edit"
        }
    }
}

#Preview("Tool call cards") {
    ScrollView {
        ToolCallCards(
            items: [
                ToolCallCardItem(
                    id: "1", kind: .find, path: "", pattern: "*.md", state: .done, summary: "3 files",
                    lines: ["notes/plan.md", "notes/trips/japan.md", "reading.md"]),
                ToolCallCardItem(
                    id: "2", kind: .read, path: "notes/plan.md", state: .done, summary: "9 lines",
                    lines: ["# Plan", "Book the ryokan.", "Book the train.", "", "## Days", "Kyoto", "Nara", "Osaka", "Home"]),
                ToolCallCardItem(
                    id: "3", kind: .edit, path: "notes/plan.md", state: .waiting,
                    diff: [
                        .init(.context, "# Plan"), .init(.removed, "Book the ryokan."), .init(.added, "Book the hotel by the river."),
                        .init(.context, "", gap: 6),
                    ], added: 1, removed: 1),
                ToolCallCardItem(id: "4", kind: .write, path: "pages/p1.json", state: .failed("pages is Hikki's own data.")),
                ToolCallCardItem(id: "5", kind: .search, path: "notes", pattern: "ryokan", state: .running),
            ], onAllow: { _ in }, onDecline: { _ in }
        )
        .padding()
    }
    .frame(width: 420, height: 720)
    .background(Theme.background)
}
