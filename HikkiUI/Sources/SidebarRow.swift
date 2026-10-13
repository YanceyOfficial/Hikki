import SwiftUI

public struct SidebarIconButton: View {
    private let title: LocalizedStringKey
    private let symbol: Icon
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, symbol: Icon, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            IconLabel(title, icon: symbol, size: TextSize.base.rawValue)
                .labelStyle(.iconOnly)
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(HoverHighlightStyle())
        .help(Text(title))
    }
}

/// Rounded hover/press highlight for plain buttons.
public struct HoverHighlightStyle: ButtonStyle {
    private let cornerRadius: CGFloat
    private let hoverFill: Color

    /// Defaults: a small chip. The sidebar footer uses `Radius.xl` + `Theme.sidebarAccent` (shadcn's
    /// `SidebarMenuButton size="lg"`).
    public init(cornerRadius: CGFloat = Radius.sm, hoverFill: Color = Theme.accent) {
        self.cornerRadius = cornerRadius
        self.hoverFill = hoverFill
    }

    public func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(configuration: configuration, cornerRadius: cornerRadius, hoverFill: hoverFill)
    }

    private struct HoverHighlight: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        let hoverFill: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(configuration.isPressed ? Theme.accentStrong : hovering ? hoverFill : .clear)
                )
                .onHover { hovering = $0 }
                .animation(Motion.easeOut(Motion.popOut), value: hovering)
        }
    }
}
