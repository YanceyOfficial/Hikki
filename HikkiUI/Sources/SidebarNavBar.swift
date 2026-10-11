import SwiftUI

/// Notion's icon row at the top of the sidebar: the selected destination expands into a pill with
/// its label; the rest are icon-only. Trailing accessory (e.g. search) sits on the right.
public struct SidebarNavBar<Trailing: View>: View {
    public struct Item: Identifiable {
        public var id: String
        public var title: String
        public var symbol: Icon
        public var isSelected: Bool
        public var action: () -> Void

        public init(id: String, title: String, symbol: Icon, isSelected: Bool, action: @escaping () -> Void) {
            self.id = id
            self.title = title
            self.symbol = symbol
            self.isSelected = isSelected
            self.action = action
        }
    }

    private let items: [Item]
    private let trailing: Trailing

    public init(_ items: [Item], @ViewBuilder trailing: () -> Trailing) {
        self.items = items
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Spacing.s1) {
            ForEach(items) { item in
                Button(action: item.action) {
                    HStack(spacing: Spacing.s1_5) {
                        IconView(item.symbol, size: TextSize.base.rawValue)
                        if item.isSelected {
                            Text(item.title).font(.hk(.sm, .semibold)).lineLimit(1)
                        }
                    }
                    .foregroundStyle(item.isSelected ? Theme.foreground : Theme.subtleForeground)
                    .padding(.horizontal, item.isSelected ? Spacing.s3 : Spacing.s2)
                    .frame(height: 32)
                    .background(item.isSelected ? Theme.accentStrong : .clear, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(HoverCapsuleStyle())
                .help(Text(item.title))
                .accessibilityLabel(item.title)
                .accessibilityIdentifier("nav-\(item.id)")
            }
            Spacer(minLength: 4)
            trailing
        }
        .animation(.snappy(duration: 0.2), value: items.map(\.isSelected))
    }
}

/// Capsule hover highlight (nav pills, bottom action pill).
public struct HoverCapsuleStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Highlight(configuration: configuration)
    }

    private struct Highlight: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(Capsule().fill(configuration.isPressed ? Theme.accentStrong : hovering ? Theme.accent : .clear))
                .onHover { hovering = $0 }
        }
    }
}

/// Big rounded action at the bottom of the sidebar (Notion's "New chat ⌘O").
/// The sidebar footer's account/workspace row (shadcn `SidebarMenuButton size="lg"`): a badge, a title
/// with a muted subtitle, and an up-down chevron. Use as the label of the footer's menu.
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

/// Notion's "Search or ask ⌘K" box at the top of the sidebar: looks like a field, opens search.
public struct SidebarSearchField: View {
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
                Text(title).font(.hk(.sm))
                Spacer(minLength: Spacing.s1)
                Text(verbatim: shortcut)
                    .font(.hk(.x2s, .medium))
                    .padding(.horizontal, Spacing.s1)
                    .padding(.vertical, Spacing.s0_5)
                    .background(Theme.accent, in: .rect(cornerRadius: Radius.sm))
            }
            .foregroundStyle(Theme.mutedForeground)
            .padding(.horizontal, Spacing.s2_5)
            .frame(height: Size.searchField)
            .background(Theme.background.opacity(0.6), in: .rect(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.border))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Sidebar search field + footer") {
    VStack(spacing: Spacing.s4) {
        GlassSearchField("Search", shortcut: "⌘K") {}
        SidebarSearchField("Search", shortcut: "⌘K") {}
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
