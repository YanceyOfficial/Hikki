import SwiftUI

/// Icon-only toolbar button with an "on" state (formatting bars, inspectors).
/// The title is kept as the accessibility label and tooltip.
public struct ToolbarIconButton: View {
    /// How the button sits in its bar: `filled` marks "on" with a tinted box (the window toolbar's); `quiet` draws
    /// every glyph in a muted ink and "on" as the glyph alone taking the tone — a keyboard bar's (Notion's), where a
    /// box would be the loudest thing on the glass — and takes the full touch target (44 pt square) for a finger.
    public enum Style: Sendable { case filled, quiet }

    private let title: LocalizedStringKey
    private let symbol: Icon
    private let isActive: Bool
    private let style: Style
    private let action: () -> Void
    @Environment(\.colorTone) private var tone

    public init(
        _ title: LocalizedStringKey, symbol: Icon, isActive: Bool = false, style: Style = .filled, action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.isActive = isActive
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            IconLabel(title, icon: symbol, size: TextSize.lg.rawValue)
                .labelStyle(.iconOnly)
                .frame(
                    width: style == .quiet ? Size.touchTarget : Size.toolbarButtonWidth,
                    height: style == .quiet ? Size.touchTarget : Size.toolbarButtonHeight
                )
                .foregroundStyle(isActive ? tone.ink : style == .quiet ? Theme.subtleForeground : .primary)
                .background(isActive && style == .filled ? tone.selectionFill : .clear, in: .rect(cornerRadius: Radius.lg))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Text(title))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

#Preview {
    VStack {
        HStack {
            ToolbarIconButton("Bold", symbol: .textB, isActive: true) {}
            ToolbarIconButton("Italic", symbol: .textItalic) {}
        }
        HStack {
            ToolbarIconButton("Bold", symbol: .textB, isActive: true, style: .quiet) {}
            ToolbarIconButton("Italic", symbol: .textItalic, style: .quiet) {}
        }
    }
    .padding()
}
