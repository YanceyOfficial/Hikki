import SwiftUI

/// Notion-style sidebar row: optional disclosure chevron, icon, title, and hover-revealed trailing
/// actions (e.g. ⋯ and +). On touch devices the actions stay hidden; use the context menu instead.
public struct SidebarRow<Actions: View>: View {
    private let title: String
    private let icon: String?
    private let systemImage: String?
    private let depth: Int
    private let isExpanded: Binding<Bool>?
    private let hasChildren: Bool
    private let isSelected: Bool
    private let shortcut: String?
    private let actions: Actions
    @State private var hovering = false

    public init(
        _ title: String,
        icon: String? = nil,
        systemImage: String? = nil,
        depth: Int = 0,
        hasChildren: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        isSelected: Bool = false,
        shortcut: String? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.systemImage = systemImage
        self.depth = depth
        self.hasChildren = hasChildren
        self.isExpanded = isExpanded
        self.isSelected = isSelected
        self.shortcut = shortcut
        self.actions = actions()
    }

    public var body: some View {
        HStack(spacing: Spacing.s2_5) {
            leadingGlyph
            Text(title.isEmpty ? String(localized: "Untitled") : title)
                .font(.hk(.sm, .medium))
                .foregroundStyle(
                    isSelected ? Theme.sidebarAccentForeground : title.isEmpty ? Theme.mutedForeground : Theme.sidebarForeground
                )
                .lineLimit(1)
            Spacer(minLength: 0)
            if let shortcut {
                Text(shortcut).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground.opacity(hovering ? 1 : 0))
            }
            // Inline and only while hovered (like Notion): the title gives up room then, and
            // there is no mask/gradient to clash with the row's hover highlight.
            if hovering {
                HStack(spacing: Spacing.s0_5) { actions }
            }
        }
        .padding(.leading, CGFloat(depth) * 14)
        .frame(minHeight: Size.row)
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }

    /// Notion-style: the page icon, which turns into the disclosure chevron while hovered.
    /// Without hover (touch), the chevron sits before the icon, and only for pages with children.
    /// Every row reserves the same fixed glyph slot, so swapping icon ↔ chevron on hover never
    /// shifts the title (it used to jitter by the 2pt difference between the two frames).
    private var glyphSlot: CGFloat { Size.sidebarIcon + Spacing.s1 }

    @ViewBuilder private var leadingGlyph: some View {
        Group {
            if let isExpanded {
                let chevron = Button {
                    withAnimation(.snappy(duration: 0.2)) { isExpanded.wrappedValue.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.hk(.x2s, .semibold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: glyphSlot, height: glyphSlot)
                        .contentShape(.rect)
                }
                .buttonStyle(HoverHighlightStyle())
                .accessibilityLabel(isExpanded.wrappedValue ? "Collapse" : "Expand")
                #if os(macOS)
                    if hovering { chevron } else { PageIcon(icon, size: Size.sidebarIcon) }
                #else
                    PageIcon(icon, size: Size.sidebarIcon)
                #endif
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.hk(.sm))
                    .foregroundStyle(Theme.subtleForeground)
            } else {
                PageIcon(icon, size: Size.sidebarIcon)
            }
        }
        .frame(width: glyphSlot, height: glyphSlot)
    }
}

/// Small square icon button used inside sidebar rows and headers.
public struct SidebarIconButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.hk(.xs, .semibold))
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
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(configuration: configuration)
    }

    private struct HoverHighlight: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(configuration.isPressed ? Theme.accentStrong : hovering ? Theme.accent : .clear)
                )
                .onHover { hovering = $0 }
        }
    }
}

#Preview {
    @Previewable @State var expanded = true
    List {
        SidebarRow("Welcome to Hikki", icon: "👋", hasChildren: true, isExpanded: $expanded) {
            SidebarIconButton("More", systemImage: "ellipsis") {}
            SidebarIconButton("Add page inside", systemImage: "plus") {}
        }
        SidebarRow("Meeting notes", icon: nil, depth: 1, isExpanded: .constant(false))
        SidebarRow("Trash", systemImage: "trash")
    }
    .frame(width: 260)
}
