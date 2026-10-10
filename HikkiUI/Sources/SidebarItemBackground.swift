import SwiftUI

/// Notion's row chrome for custom (non-List) sidebars: inset rounded highlight on hover/selection.
struct SidebarItemBackground: ViewModifier {
    let isSelected: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
                    .fill(isSelected ? Theme.selected : hovering ? Theme.hover : .clear)
            )
            .padding(.horizontal, 6)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Hover/selection highlight for a row in a custom sidebar.
    public func sidebarItemBackground(isSelected: Bool = false) -> some View {
        modifier(SidebarItemBackground(isSelected: isSelected))
    }
}
