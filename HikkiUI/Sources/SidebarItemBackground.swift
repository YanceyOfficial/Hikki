import SwiftUI

/// Notion's row chrome for custom (non-List) sidebars: inset rounded highlight on hover/selection.
struct SidebarItemBackground: ViewModifier {
    let isSelected: Bool
    var highlight: Color?
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.s2)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(highlight ?? (isSelected ? Theme.accentStrong : hovering ? Theme.accent : .clear))
            )
            .padding(.horizontal, Spacing.s1_5)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Hover/selection highlight for a row in a custom sidebar.
    public func sidebarItemBackground(isSelected: Bool = false, highlight: Color? = nil) -> some View {
        modifier(SidebarItemBackground(isSelected: isSelected, highlight: highlight))
    }
}
