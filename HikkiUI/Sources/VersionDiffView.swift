import SwiftUI

/// A version of a page as text blocks (page history's preview), each marked against the page as it is now: text only
/// the version has is washed green (restoring brings it back), text only the current page has is struck through in
/// red (restoring removes it). Plain values: the app flattens and compares the pages (HikkiCore's `PageDiff`).
public struct VersionDiffView: View {
    public enum Style: Sendable, Equatable {
        case paragraph, heading1, heading2, heading3, bullet, numbered, task, taskDone, quote, code, table, media, rule
    }

    public enum Change: Sendable, Equatable {
        case same, added, removed
    }

    public struct Run: Sendable, Equatable {
        public var text: String
        public var change: Change

        public init(_ text: String, _ change: Change) {
            self.text = text
            self.change = change
        }
    }

    public struct Block: Sendable, Equatable, Identifiable {
        public var id: Int
        public var style: Style
        public var depth: Int
        /// The block as a whole: added or removed blocks are tinted edge to edge, edited ones only in their runs.
        public var change: Change
        public var runs: [Run]

        public init(id: Int, style: Style, depth: Int = 0, change: Change = .same, runs: [Run]) {
            self.id = id
            self.style = style
            self.depth = depth
            self.change = change
            self.runs = runs
        }
    }

    private let blocks: [Block]
    private let showsChanges: Bool

    /// `showsChanges` false: the version as it was, no marks.
    public init(blocks: [Block], showsChanges: Bool = true) {
        self.blocks = blocks
        self.showsChanges = showsChanges
    }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.s2) {
            ForEach(blocks.filter { showsChanges || $0.change != .removed }) { block in
                row(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func row(_ block: Block) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            if let marker = marker(block.style) {
                Text(verbatim: marker).foregroundStyle(Theme.mutedForeground)
            }
            if block.style == .rule {
                Rectangle().fill(Theme.border).frame(height: Spacing.px).frame(maxWidth: .infinity)
            } else {
                Text(text(block))
                    .font(font(block.style))
                    .strikethrough(block.style == .taskDone, color: Theme.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, CGFloat(block.depth) * Spacing.s5)
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, block.style == .code || block.style == .quote ? Spacing.s1 : Spacing.s0)
        .background(background(block), in: .rect(cornerRadius: Radius.sm))
        .overlay(alignment: .leading) {
            if block.style == .quote {
                Rectangle().fill(Theme.foreground).frame(width: Spacing.s0_5)
            }
        }
    }

    private func text(_ block: Block) -> AttributedString {
        var result = AttributedString()
        for run in block.runs {
            var piece = AttributedString(run.text)
            if showsChanges, block.change == .same {
                switch run.change {
                case .same: break
                case .added: piece.backgroundColor = Theme.washGreen
                case .removed:
                    piece.strikethroughStyle = .single
                    piece.foregroundColor = Theme.inkRed
                }
            }
            result += piece
        }
        if block.runs.allSatisfy({ $0.text.isEmpty }) { result = AttributedString(" ") }
        if showsChanges, block.change == .removed {
            result.strikethroughStyle = .single
            result.foregroundColor = Theme.inkRed
        }
        return result
    }

    private func background(_ block: Block) -> Color {
        if showsChanges {
            switch block.change {
            case .added: return Theme.washGreen
            case .removed: return Theme.washRed
            case .same: break
            }
        }
        return block.style == .code ? Theme.code : .clear
    }

    private func marker(_ style: Style) -> String? {
        switch style {
        case .bullet: "•"
        case .numbered: "–"
        case .task: "☐"
        case .taskDone: "☑"
        case .media: "▣"
        default: nil
        }
    }

    private func font(_ style: Style) -> Font {
        switch style {
        case .heading1: .hk(.x2l, .bold)
        case .heading2: .hk(.xl, .semibold)
        case .heading3: .hk(.lg, .semibold)
        case .code, .table: .hk(.sm, design: .monospaced)
        case .media: .hk(.sm).italic()
        default: .hk(.base)
        }
    }
}

/// A version's title in page history's preview. Without `runs` (the title didn't change) it is the version's title;
/// with them it is marked like the body below it — what only the version has washed green, what only the current
/// page has struck through in red — under a small "Title changed" line. `showsChanges` false: the version's title, no
/// marks.
public struct VersionTitleView: View {
    private let title: String
    private let runs: [VersionDiffView.Run]?
    private let placeholder: String
    private let showsChanges: Bool

    public init(title: String, runs: [VersionDiffView.Run]? = nil, placeholder: String, showsChanges: Bool = true) {
        self.title = title
        self.runs = runs
        self.placeholder = placeholder
        self.showsChanges = showsChanges
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            if marked {
                Text("app:history.titleChanged")
                    .font(.hk(.xs, .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityIdentifier("history-title-changed")
            }
            Text(text)
                .font(.hk(.x3l, .bold))
                .foregroundStyle(title.isEmpty && !marked ? Theme.placeholder : Theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("history-title")
        }
        .textSelection(.enabled)
    }

    private var marked: Bool { showsChanges && runs != nil }

    private var text: AttributedString {
        guard marked, let runs else { return AttributedString(title.isEmpty ? placeholder : title) }
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            switch run.change {
            case .same: break
            case .added: piece.backgroundColor = Theme.washGreen
            case .removed:
                piece.strikethroughStyle = .single
                piece.foregroundColor = Theme.inkRed
            }
            result += piece
        }
        // The version had no title (every word is the current page's): "Untitled" follows them.
        if !runs.contains(where: { $0.change != .removed }) {
            var untitled = AttributedString(" " + placeholder)
            untitled.foregroundColor = Theme.placeholder
            result += untitled
        }
        return result
    }
}

#Preview("Title") {
    VStack(alignment: .leading, spacing: Spacing.s4) {
        VersionTitleView(
            title: "Trip to Kyoto", runs: [.init("Trip to ", .same), .init("Osaka", .removed), .init("Kyoto", .added)],
            placeholder: "Untitled")
        VersionTitleView(title: "", runs: [.init("Plans", .removed)], placeholder: "Untitled")
        VersionTitleView(title: "Unchanged", placeholder: "Untitled")
    }
    .padding()
}

#Preview {
    ScrollView {
        VersionDiffView(blocks: [
            .init(id: 0, style: .heading1, runs: [.init("Trip to Kyoto", .same)]),
            .init(
                id: 1, style: .paragraph,
                runs: [.init("We leave on ", .same), .init("Friday", .removed), .init("Saturday", .added), .init(" morning.", .same)]),
            .init(id: 2, style: .bullet, change: .added, runs: [.init("Book the ryokan", .added)]),
            .init(id: 3, style: .taskDone, depth: 1, runs: [.init("Passport", .same)]),
            .init(id: 4, style: .paragraph, change: .removed, runs: [.init("An old note", .removed)]),
            .init(id: 5, style: .code, runs: [.init("let x = 1", .same)]),
        ])
        .padding()
    }
}
