import SwiftUI

/// Icon-only toolbar button with an "on" state (formatting bars, inspectors).
/// The title is kept as the accessibility label and tooltip.
public struct ToolbarIconButton: View {
    private let title: LocalizedStringKey
    private let symbol: Icon
    private let isActive: Bool
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, symbol: Icon, isActive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            IconLabel(title, icon: symbol, size: TextSize.lg.rawValue)
                .labelStyle(.iconOnly)
                .frame(width: 40, height: 36)
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .background(isActive ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: Radius.lg))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Text(title))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

#Preview {
    HStack {
        ToolbarIconButton("Bold", symbol: .textB, isActive: true) {}
        ToolbarIconButton("Italic", symbol: .textItalic) {}
    }
    .padding()
}
