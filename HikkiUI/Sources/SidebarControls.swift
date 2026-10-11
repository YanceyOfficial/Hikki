import SwiftUI

public struct SidebarFooterLabel<Badge: View>: View {
    private let title: String
    private let subtitle: String
    private let badge: Badge

    /// `title` / `subtitle` are shown as-is (a workspace name, a folder path): pass already-localized text.
    public init(title: String, subtitle: String, @ViewBuilder badge: () -> Badge) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge()
    }

    public var body: some View {
        HStack(spacing: Spacing.s2) {
            badge
            VStack(alignment: .leading, spacing: Spacing.px) {
                Text(verbatim: title).font(.hk(.sm, .medium)).foregroundStyle(Theme.foreground)
                Text(verbatim: subtitle).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
            }
            .lineLimit(1)
            Spacer(minLength: Spacing.s1)
            IconView(.caretUpDown, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
        }
        .padding(.horizontal, Spacing.s2)
        .frame(height: Size.sidebarFooter)
        .contentShape(.rect)
    }
}

/// A search "field" in Liquid Glass that opens search when clicked (no typing in place) — Apple Music's
/// sidebar search, for a native sidebar.
public struct GlassSearchField: View {
    private let title: LocalizedStringKey
    private let shortcut: String
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, shortcut: String, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s2) {
                IconView(.magnifyingGlass, size: TextSize.base.rawValue)
                Text(title)
                Spacer(minLength: Spacing.s1)
                Text(verbatim: shortcut).font(.hk(.xs, .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.s3)
            .frame(height: Size.searchField)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

#Preview("Sidebar search field + footer") {
    VStack(spacing: Spacing.s4) {
        GlassSearchField("Search", shortcut: "⌘K") {}
        Button {
        } label: {
            SidebarFooterLabel(title: "Yancey’s Space", subtitle: "This device only") {
                Text(verbatim: "Y").frame(width: 32, height: 32).background(ColorTone.standard.fill, in: .rect(cornerRadius: Radius.lg))
            }
        }
        .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.xl, hoverFill: Theme.sidebarAccent))
    }
    .padding(Spacing.s3)
    .frame(width: 280)
    .background(Theme.sidebar)
}
