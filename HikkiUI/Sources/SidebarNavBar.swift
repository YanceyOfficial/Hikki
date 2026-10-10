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
public struct SidebarActionPill: View {
    private let title: LocalizedStringKey
    private let symbol: Icon
    private let shortcut: String?
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, symbol: Icon, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s2) {
                IconView(symbol, size: TextSize.sm.rawValue)
                Text(title).font(.hk(.sm, .medium))
                if let shortcut {
                    Text(shortcut)
                        .font(.hk(.x2s, .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.horizontal, Spacing.s1)
                        .padding(.vertical, Spacing.s0_5)
                        .background(Theme.accent, in: .rect(cornerRadius: Radius.sm))
                }
            }
            .foregroundStyle(Theme.foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Theme.popover, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .contentShape(.capsule)
        }
        .buttonStyle(HoverCapsuleStyle())
    }
}
