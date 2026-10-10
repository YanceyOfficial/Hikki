import SwiftUI

/// Notion's icon row at the top of the sidebar: the selected destination expands into a pill with
/// its label; the rest are icon-only. Trailing accessory (e.g. search) sits on the right.
public struct SidebarNavBar<Trailing: View>: View {
    public struct Item: Identifiable {
        public var id: String
        public var title: String
        public var systemImage: String
        public var isSelected: Bool
        public var action: () -> Void

        public init(id: String, title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
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
        HStack(spacing: 4) {
            ForEach(items) { item in
                Button(action: item.action) {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 15, weight: item.isSelected ? .semibold : .regular))
                        if item.isSelected {
                            Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        }
                    }
                    .foregroundStyle(item.isSelected ? Theme.text : Theme.secondaryText)
                    .padding(.horizontal, item.isSelected ? 12 : 8)
                    .frame(height: 32)
                    .background(item.isSelected ? Theme.selected : .clear, in: .capsule)
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
                .background(Capsule().fill(configuration.isPressed ? Theme.selected : hovering ? Theme.hover : .clear))
                .onHover { hovering = $0 }
        }
    }
}

/// Big rounded action at the bottom of the sidebar (Notion's "New chat ⌘O").
public struct SidebarActionPill: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let shortcut: String?
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, systemImage: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 14))
                Text(title).font(.system(size: 14, weight: .medium))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.mutedText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.hover, in: .rect(cornerRadius: 4))
                }
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Theme.elevated, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .contentShape(.capsule)
        }
        .buttonStyle(HoverCapsuleStyle())
    }
}
