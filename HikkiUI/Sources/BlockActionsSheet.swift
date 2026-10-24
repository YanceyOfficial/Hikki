import SwiftUI

/// What the ⋯ sheet knows of the block at the caret: its kind (the section title), what applies to it, its colours
/// and its words and characters.
public struct BlockActionsInfo: Equatable, Sendable {
    public var kind: String
    /// Its catalog id when it can turn into another block (nil: it can't).
    public var turnInto: String?
    public var turnIntoItems: [KeyboardBlockItem]
    public var textColor: String?
    public var backgroundColor: String?
    public var colorable: Bool
    public var copyLink: Bool
    public var comment: Bool
    public var askAI: Bool
    public var words: Int?
    public var characters: Int?
    /// The pages it can move to (none: no Move to — a read-only page, or no other page).
    public var moveTargets: [PageChoice]

    public init(
        kind: String, turnInto: String?, turnIntoItems: [KeyboardBlockItem], textColor: String?, backgroundColor: String?,
        colorable: Bool, copyLink: Bool, comment: Bool, askAI: Bool, words: Int?, characters: Int?,
        moveTargets: [PageChoice] = []
    ) {
        self.moveTargets = moveTargets
        self.kind = kind
        self.turnInto = turnInto
        self.turnIntoItems = turnIntoItems
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.colorable = colorable
        self.copyLink = copyLink
        self.comment = comment
        self.askAI = askAI
        self.words = words
        self.characters = characters
    }
}

/// A page to pick (Move to): its id, title (empty: untitled) and icon.
public struct PageChoice: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let icon: String?

    public init(id: String, title: String, icon: String?) {
        self.id = id
        self.title = title
        self.icon = icon
    }
}

/// The sheet's actions that need no further choice (Turn into and Color open their own lists).
public enum BlockAction: String, Sendable {
    case insertBelow, copyLink, duplicate, delete, comment, askAI
}

/// The phone's ⋯ on the keyboard bar (Notion's block actions): Turn into, Color, Insert below; Copy link, Duplicate,
/// Move to, Delete; Comment; Ask AI — the block's words and characters at the foot. Each action closes the sheet.
public struct BlockActionsSheet: View {
    let info: BlockActionsInfo
    let onAction: (BlockAction) -> Void
    let onTurnInto: (String) -> Void
    let onColor: (KeyboardFormatPanel.ColorKind, String?) -> Void
    let onMove: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(
        info: BlockActionsInfo, onAction: @escaping (BlockAction) -> Void, onTurnInto: @escaping (String) -> Void,
        onColor: @escaping (KeyboardFormatPanel.ColorKind, String?) -> Void, onMove: @escaping (String) -> Void = { _ in }
    ) {
        self.info = info
        self.onAction = onAction
        self.onTurnInto = onTurnInto
        self.onColor = onColor
        self.onMove = onMove
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    if info.turnInto != nil {
                        NavigationLink {
                            TurnIntoList(items: info.turnIntoItems, current: info.turnInto) { onTurnInto($0) }
                        } label: {
                            IconLabel("app:keyboard.turnInto", icon: .arrowsClockwise)
                        }
                        .accessibilityIdentifier("block-action-turnInto")
                    }
                    if info.colorable {
                        NavigationLink {
                            BlockColorList(text: info.textColor, background: info.backgroundColor) { onColor($0, $1) }
                        } label: {
                            IconLabel("app:keyboard.color", icon: .paintBrush)
                        }
                        .accessibilityIdentifier("block-action-color")
                    }
                    row(.insertBelow, "app:blockActions.insertBelow", icon: .arrowDown)
                } header: {
                    Text(verbatim: info.kind)
                }
                Section {
                    if info.copyLink { row(.copyLink, "app:blockActions.copyLink", icon: .link) }
                    row(.duplicate, "app:page.duplicate", icon: .copy)
                    if !info.moveTargets.isEmpty {
                        NavigationLink {
                            PageChoiceList(pages: info.moveTargets) { page in
                                dismiss()
                                onMove(page)
                            }
                        } label: {
                            IconLabel("app:page.moveTo", icon: .arrowBendUpRight)
                        }
                        .accessibilityIdentifier("block-action-moveTo")
                    }
                    row(.delete, "app:common.delete", icon: .trash, role: .destructive)
                }
                if info.comment {
                    Section { row(.comment, "app:keyboard.comment", icon: .chatTeardropText) }
                }
                if info.askAI {
                    Section { row(.askAI, "app:keyboard.askAI", icon: .sparkle) }
                }
                if let words = info.words, let characters = info.characters {
                    Section {
                        Text("app:page.stats \(words.formatted()) \(characters.formatted())")
                            .font(.hk(.sm))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
            #if os(iOS)
                .listStyle(.insetGrouped)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle(Text("app:blockActions.title"))
        }
        .accessibilityIdentifier("block-actions-sheet")
    }

    private func row(_ action: BlockAction, _ title: LocalizedStringKey, icon: Icon, role: ButtonRole? = nil) -> some View {
        Button(role: role) {
            dismiss()
            onAction(action)
        } label: {
            IconLabel(title, icon: icon)
                .foregroundStyle(role == .destructive ? Theme.destructive : Theme.foreground)
        }
        .accessibilityIdentifier("block-action-\(action.rawValue)")
    }
}

/// Move to: every other page, searchable by title; a pick closes the sheet.
private struct PageChoiceList: View {
    let pages: [PageChoice]
    let onPick: (String) -> Void
    @State private var query = ""

    private var shown: [PageChoice] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return pages }
        return pages.filter { title($0).localizedStandardContains(q) }
    }

    private func title(_ page: PageChoice) -> String { PageTitle.display(page.title) }

    var body: some View {
        List(shown) { page in
            Button {
                onPick(page.id)
            } label: {
                HStack(spacing: Spacing.s3) {
                    Text(verbatim: page.icon ?? "📄").frame(width: Spacing.s6)
                    Text(verbatim: title(page)).foregroundStyle(Theme.foreground).lineLimit(1)
                }
            }
            .accessibilityIdentifier("block-move-\(page.id)")
        }
        .searchable(text: $query, prompt: Text("app:blockActions.searchPages"))
        .navigationTitle(Text("app:page.moveTo"))
    }
}

/// Turn into: the blocks with text, the current one checked; a pick closes the sheet.
private struct TurnIntoList: View {
    let items: [KeyboardBlockItem]
    let current: String?
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorTone) private var tone

    var body: some View {
        List(items) { item in
            Button {
                dismiss()
                onPick(item.id)
            } label: {
                HStack {
                    IconView(item.icon ?? .plus, size: TextSize.lg.rawValue)
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: Spacing.s6)
                    Text(verbatim: item.label).foregroundStyle(Theme.foreground)
                    Spacer(minLength: Spacing.s0)
                    if item.id == current { IconView(.check, size: TextSize.base.rawValue).foregroundStyle(tone.fill) }
                }
            }
            .accessibilityIdentifier("block-turn-\(item.id)")
        }
        .navigationTitle(Text("app:keyboard.turnInto"))
    }
}

/// Color: the block's text colour and its background, each a list of the palette, the current one checked.
private struct BlockColorList: View {
    let text: String?
    let background: String?
    let onPick: (KeyboardFormatPanel.ColorKind, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorTone) private var tone

    var body: some View {
        List {
            Section("app:keyboard.textColor") { rows(.text, current: text) }
            Section("app:keyboard.background") { rows(.background, current: background) }
        }
        .navigationTitle(Text("app:keyboard.color"))
    }

    private func rows(_ kind: KeyboardFormatPanel.ColorKind, current: String?) -> some View {
        ForEach([nil] + PanelPalette.names, id: \.self) { (name: String?) in
            Button {
                dismiss()
                onPick(kind, name)
            } label: {
                HStack(spacing: Spacing.s3) {
                    Text(verbatim: "A")
                        .font(.hk(.base, .semibold))
                        .foregroundStyle(kind == .text ? PanelPalette.ink(name) : Theme.foreground)
                        .frame(width: Spacing.s7, height: Spacing.s7)
                        .background(
                            kind == .background ? PanelPalette.wash(name) : Theme.background, in: .rect(cornerRadius: Radius.md)
                        )
                        .overlay { RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.border, lineWidth: Spacing.px) }
                    Text(PanelPalette.label(name)).foregroundStyle(Theme.foreground)
                    Spacer(minLength: Spacing.s0)
                    if name == current { IconView(.check, size: TextSize.base.rawValue).foregroundStyle(tone.fill) }
                }
            }
        }
    }
}

#Preview {
    BlockActionsSheet(
        info: .init(
            kind: "Quote", turnInto: "blockquote",
            turnIntoItems: [.init(id: "paragraph", label: "Text", icon: .textT), .init(id: "blockquote", label: "Quote", icon: .quotes)],
            textColor: nil, backgroundColor: "yellow", colorable: true, copyLink: true, comment: true, askAI: true, words: 29,
            characters: 56, moveTargets: [.init(id: "a", title: "Trip to Kyoto", icon: "🗾"), .init(id: "b", title: "", icon: nil)]),
        onAction: { _ in }, onTurnInto: { _ in }, onColor: { _, _ in })
}
