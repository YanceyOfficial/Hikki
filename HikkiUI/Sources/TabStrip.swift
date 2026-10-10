import SwiftUI

/// One tab in a `TabStrip`.
public struct TabStripItem: Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var icon: String?
    public var systemImage: String?

    public init(id: UUID, title: String, icon: String? = nil, systemImage: String? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.systemImage = systemImage
    }
}

/// Browser-style tab bar (Notion's top row): back/forward, tabs that shrink to fit, close on hover, "+".
/// Purely presentational — all state lives with the caller.
public struct TabStrip<Leading: View>: View {
    private let items: [TabStripItem]
    private let activeID: UUID
    private let canGoBack: Bool
    private let canGoForward: Bool
    private let onSelect: (UUID) -> Void
    private let onClose: (UUID) -> Void
    private let onNew: () -> Void
    private let onBack: () -> Void
    private let onForward: () -> Void
    private let leading: Leading
    @Environment(\.chromeMetrics) private var metrics

    public init(
        items: [TabStripItem], activeID: UUID, canGoBack: Bool, canGoForward: Bool,
        onSelect: @escaping (UUID) -> Void, onClose: @escaping (UUID) -> Void, onNew: @escaping () -> Void,
        onBack: @escaping () -> Void, onForward: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading = { EmptyView() }
    ) {
        self.items = items
        self.activeID = activeID
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.onSelect = onSelect
        self.onClose = onClose
        self.onNew = onNew
        self.onBack = onBack
        self.onForward = onForward
        self.leading = leading()
    }

    public static var height: CGFloat { 40 }

    public var body: some View {
        HStack(spacing: Spacing.s1) {
            leading
            SidebarIconButton("Back", systemImage: "chevron.left", action: onBack)
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.4)
            SidebarIconButton("Forward", systemImage: "chevron.right", action: onForward)
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.4)
            HStack(spacing: Spacing.s0_5) {
                ForEach(items) { item in
                    TabButton(item: item, isActive: item.id == activeID, canClose: items.count > 1,
                              onSelect: { onSelect(item.id) }, onClose: { onClose(item.id) })
                }
            }
            SidebarIconButton("New Tab", systemImage: "plus", action: onNew)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, Spacing.s2)
        .frame(height: metrics.barHeight)
    }
}

private struct TabButton: View {
    let item: TabStripItem
    let isActive: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.s1_5) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage).font(.hk(.sm)).foregroundStyle(Theme.subtleForeground)
            } else {
                PageIcon(item.icon, size: 13)
            }
            Text(item.title.isEmpty ? String(localized: "Untitled") : item.title)
                .font(.hk(.md, isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Theme.foreground : Theme.subtleForeground)
                .lineLimit(1)
            Spacer(minLength: 0)
            if canClose && (hovering || isActive) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.hk(.x2s, .bold))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 16, height: 16)
                        .contentShape(.rect)
                }
                .buttonStyle(HoverHighlightStyle())
                .accessibilityLabel("Close Tab")
            }
        }
        .padding(.horizontal, Spacing.s2_5)
        .frame(minWidth: 60, idealWidth: 200, maxWidth: 220, minHeight: 30, maxHeight: 30)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(isActive ? Theme.background : hovering ? Theme.accent : .clear)
                .shadow(color: isActive ? .black.opacity(0.08) : .clear, radius: 1, y: 0.5)
        )
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Close Tab", onClose)
    }
}

#Preview {
    let a = UUID(), b = UUID()
    TabStrip(
        items: [TabStripItem(id: a, title: "Welcome to Hikki", icon: "👋"), TabStripItem(id: b, title: "", systemImage: "house")],
        activeID: a, canGoBack: true, canGoForward: false,
        onSelect: { _ in }, onClose: { _ in }, onNew: {}, onBack: {}, onForward: {}
    )
    .background(Theme.sidebar)
    .frame(width: 700)
}
