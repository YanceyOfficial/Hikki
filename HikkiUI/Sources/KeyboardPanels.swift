import SwiftUI

/// A block in a keyboard panel: its id (the editor's catalog), name and icon (nil: a generic one).
public struct KeyboardBlockItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var icon: Icon?

    public init(id: String, label: String, icon: Icon?) {
        self.id = id
        self.label = label
        self.icon = icon
    }
}

public struct KeyboardBlockSection: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var items: [KeyboardBlockItem]

    public init(id: String, title: String, items: [KeyboardBlockItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// The phone's "+" panel, in the keyboard's place: the block catalog as flat two-column rows (icon + name, Notion's),
/// grouped as the "/" menu is. Also the bar's Turn into, with the block's current kind marked (`current`).
public struct KeyboardBlockPanel: View {
    let sections: [KeyboardBlockSection]
    let current: String?
    let onPick: (String) -> Void

    public init(sections: [KeyboardBlockSection], current: String? = nil, onPick: @escaping (String) -> Void) {
        self.sections = sections
        self.current = current
        self.onPick = onPick
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s2) {
                ForEach(sections) { section in
                    PanelTitle(verbatim: section.title)
                    BlockGrid(items: section.items, current: current, onPick: onPick)
                        .padding(.bottom, Spacing.s2)
                }
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s3)
        }
        .background(Theme.background)
        .accessibilityIdentifier("keyboard-block-panel")
    }
}

/// The phone's "Aa" panel, in the keyboard's place: the marks, Turn into, then text colour and background — each tap
/// applies at once and the panel stays.
public struct KeyboardFormatPanel: View {
    public enum Mark: String, CaseIterable, Sendable {
        case bold, italic, underline, strike, code, link

        var icon: Icon {
            switch self {
            case .bold: .textB
            case .italic: .textItalic
            case .underline: .textUnderline
            case .strike: .textStrikethrough
            case .code: .code
            case .link: .link
            }
        }

        var label: LocalizedStringKey {
            switch self {
            case .bold: "app:format.bold"
            case .italic: "app:format.italic"
            case .underline: "app:format.underline"
            case .strike: "app:format.strikethrough"
            case .code: "app:format.inlineCode"
            case .link: "app:format.link"
            }
        }
    }

    public enum ColorKind: Sendable { case text, background }

    let marks: Set<Mark>
    let turnInto: [KeyboardBlockItem]
    let block: String
    let textColor: String?
    let backgroundColor: String?
    let onMark: (Mark) -> Void
    let onTurnInto: (String) -> Void
    let onColor: (ColorKind, String?) -> Void
    @Environment(\.colorTone) private var tone

    public init(
        marks: Set<Mark>, turnInto: [KeyboardBlockItem], block: String, textColor: String?, backgroundColor: String?,
        onMark: @escaping (Mark) -> Void, onTurnInto: @escaping (String) -> Void,
        onColor: @escaping (ColorKind, String?) -> Void
    ) {
        self.marks = marks
        self.turnInto = turnInto
        self.block = block
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.onMark = onMark
        self.onTurnInto = onTurnInto
        self.onColor = onColor
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(spacing: Spacing.s0_5) {
                    ForEach(Mark.allCases, id: \.self) { mark in
                        let on = marks.contains(mark)
                        Button {
                            onMark(mark)
                        } label: {
                            IconView(mark.icon, size: TextSize.lg.rawValue)
                                .frame(maxWidth: .infinity, minHeight: Size.toolbarButtonHeight)
                                .foregroundStyle(on ? tone.ink : Theme.foreground)
                                .background(on ? tone.selectionFill : .clear, in: .rect(cornerRadius: Radius.md))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(mark.label))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(Spacing.s1)
                .background(Theme.muted, in: .rect(cornerRadius: Radius.lg))
                .padding(.bottom, Spacing.s2)

                PanelTitle("app:keyboard.turnInto")
                BlockGrid(items: turnInto, current: block, onPick: onTurnInto)
                    .padding(.bottom, Spacing.s2)

                PanelTitle("app:keyboard.textColor")
                swatches(.text, current: textColor)
                    .padding(.bottom, Spacing.s2)
                PanelTitle("app:keyboard.background")
                swatches(.background, current: backgroundColor)
            }
            .padding(Spacing.s3)
        }
        .background(Theme.background)
        .accessibilityIdentifier("keyboard-format-panel")
    }

    private func swatches(_ kind: ColorKind, current: String?) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s2), count: 5), spacing: Spacing.s2) {
            ForEach([nil] + PanelPalette.names, id: \.self) { (name: String?) in
                let on = name == current
                Button {
                    onColor(kind, name)
                } label: {
                    Text(verbatim: "A")
                        .font(.hk(.base, .semibold))
                        .foregroundStyle(kind == .text ? PanelPalette.ink(name) : Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: Size.toolbarButtonHeight)
                        .background(
                            kind == .background ? PanelPalette.wash(name) : Theme.background,
                            in: .rect(cornerRadius: Radius.md)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.md)
                                .strokeBorder(on ? tone.fill : Theme.border, lineWidth: on ? Spacing.s0_5 : Spacing.px)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(PanelPalette.label(name)))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A panel's section title.
private struct PanelTitle: View {
    let text: Text

    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }

    var body: some View {
        text.font(.hk(.xs, .medium)).foregroundStyle(Theme.mutedForeground).padding(.horizontal, Spacing.s1)
    }
}

/// Blocks as flat rows, two to a line; the current one (Turn into) marked.
private struct BlockGrid: View {
    let items: [KeyboardBlockItem]
    let current: String?
    let onPick: (String) -> Void
    @Environment(\.colorTone) private var tone

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.s1_5), GridItem(.flexible())], spacing: Spacing.s1_5) {
            ForEach(items) { item in
                let on = item.id == current
                Button {
                    onPick(item.id)
                } label: {
                    HStack(spacing: Spacing.s2_5) {
                        IconView(item.icon ?? .plus, size: TextSize.lg.rawValue)
                            .foregroundStyle(on ? tone.ink : Theme.mutedForeground)
                            .frame(width: Spacing.s6)
                        Text(verbatim: item.label)
                            .font(.hk(.sm, .medium))
                            .foregroundStyle(on ? tone.ink : Theme.foreground)
                            .lineLimit(1)
                        Spacer(minLength: Spacing.s0)
                    }
                    .padding(.horizontal, Spacing.s2_5)
                    .frame(minHeight: Size.toolbarButtonHeight + Spacing.s2)
                    .background(on ? tone.selectionFill : Theme.background, in: .rect(cornerRadius: Radius.lg))
                    .overlay { RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.border, lineWidth: Spacing.px) }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("keyboard-block-\(item.id)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// The editor's palette (names stored in the page, `colors.ts`) as the panels draw it.
enum PanelPalette {
    static let names = ["gray", "brown", "orange", "yellow", "green", "blue", "purple", "pink", "red"]

    static func ink(_ name: String?) -> Color {
        switch name {
        case "gray": Theme.inkGray
        case "brown": Theme.inkBrown
        case "orange": Theme.inkOrange
        case "yellow": Theme.inkYellow
        case "green": Theme.inkGreen
        case "blue": Theme.inkBlue
        case "purple": Theme.inkPurple
        case "pink": Theme.inkPink
        case "red": Theme.inkRed
        default: Theme.foreground
        }
    }

    static func wash(_ name: String?) -> Color {
        switch name {
        case "gray": Theme.washGray
        case "brown": Theme.washBrown
        case "orange": Theme.washOrange
        case "yellow": Theme.washYellow
        case "green": Theme.washGreen
        case "blue": Theme.washBlue
        case "purple": Theme.washPurple
        case "pink": Theme.washPink
        case "red": Theme.washRed
        default: Theme.background
        }
    }

    static func label(_ name: String?) -> LocalizedStringResource {
        switch name {
        case "gray": "app:color.gray"
        case "brown": "app:color.brown"
        case "orange": "app:color.orange"
        case "yellow": "app:color.yellow"
        case "green": "app:color.green"
        case "blue": "app:color.blue"
        case "purple": "app:color.purple"
        case "pink": "app:color.pink"
        case "red": "app:color.red"
        default: "app:color.default"
        }
    }
}

#Preview("+ panel") {
    KeyboardBlockPanel(
        sections: [
            .init(
                id: "basic", title: "Basic blocks",
                items: [
                    .init(id: "paragraph", label: "Text", icon: .textT), .init(id: "heading1", label: "Heading 1", icon: .textHOne),
                    .init(id: "heading2", label: "Heading 2", icon: .textHTwo),
                    .init(id: "heading3", label: "Heading 3", icon: .textHThree),
                ]),
            .init(
                id: "lists", title: "Lists",
                items: [
                    .init(id: "bulletList", label: "Bulleted list", icon: .listBullets),
                    .init(id: "taskList", label: "To-do list", icon: .checkSquare),
                    .init(id: "toggle", label: "Toggle list", icon: .caretCircleRight),
                ]),
        ], onPick: { _ in }
    )
    .frame(height: 300)
}

#Preview("Aa panel") {
    KeyboardFormatPanel(
        marks: [.bold],
        turnInto: [.init(id: "paragraph", label: "Text", icon: .textT), .init(id: "heading1", label: "Heading 1", icon: .textHOne)],
        block: "paragraph", textColor: "red", backgroundColor: nil, onMark: { _ in }, onTurnInto: { _ in }, onColor: { _, _ in }
    )
    .frame(height: 300)
}
