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
    private let actions: Actions
    @State private var hovering = false

    public init(
        _ title: String,
        icon: String? = nil,
        systemImage: String? = nil,
        depth: Int = 0,
        hasChildren: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.systemImage = systemImage
        self.depth = depth
        self.hasChildren = hasChildren
        self.isExpanded = isExpanded
        self.actions = actions()
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let isExpanded {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { isExpanded.wrappedValue.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        .foregroundStyle(Theme.mutedText)
                        .frame(width: 16, height: 16)
                        .opacity(hasChildren ? 1 : 0.35)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded.wrappedValue ? "Collapse" : "Expand")
            }
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 20, height: 20)
            } else {
                PageIcon(icon)
            }
            Text(title.isEmpty ? String(localized: "Untitled") : title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(title.isEmpty ? Theme.mutedText : Theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 14)
        .frame(minHeight: Theme.Metrics.rowHeight)
        // Overlaid, not inline: hidden actions must not steal width from the title.
        .overlay(alignment: .trailing) {
            if hovering {
                HStack(spacing: 2) { actions }
                    .padding(.leading, 12)
                    .background(alignment: .leading) {
                        LinearGradient(colors: [Theme.sidebar.opacity(0), Theme.sidebar], startPoint: .leading, endPoint: UnitPoint(x: 0.3, y: 0.5))
                    }
            }
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.mutedText)
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
                    RoundedRectangle(cornerRadius: 4)
                        .fill(configuration.isPressed ? Theme.selected : hovering ? Theme.hover : .clear)
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
