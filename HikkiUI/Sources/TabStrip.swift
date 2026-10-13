import SwiftUI
import UniformTypeIdentifiers

/// One tab in a `TabStrip`.
public struct TabStripItem: Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var icon: String?
    public var symbol: Icon?

    public init(id: UUID, title: String, icon: String? = nil, symbol: Icon? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.symbol = symbol
    }
}

/// Where a drag over a `TabStrip` would land: on a tab (it shows the dropped page), or in the gap before
/// the tab at `index` (`items.count` = after the last one).
public enum TabStripDropTarget: Equatable, Sendable {
    case onto(UUID)
    case between(Int)
}

/// What a `TabStrip` takes from a drag: the pasteboard types it answers to, whether the drag in progress
/// is wanted at all (the caller knows what is being dragged), and what to do where it lands.
public struct TabStripDrop {
    public var types: [UTType]
    public var accepts: () -> Bool
    public var perform: (TabStripDropTarget) -> Bool

    public init(types: [UTType], accepts: @escaping () -> Bool, perform: @escaping (TabStripDropTarget) -> Bool) {
        self.types = types
        self.accepts = accepts
        self.perform = perform
    }
}

/// Browser-style tab bar (Notion's top row): back/forward, tabs that shrink to fit, close on hover, "+".
/// Purely presentational — all state lives with the caller. With `drop`, a page dragged over it shows a
/// line between tabs or a tint on one (Safari's tab bar), and the caller gets where it landed.
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
    private let showsHistory: Bool
    private let drop: TabStripDrop?
    @State private var frames: [UUID: CGRect] = [:]
    @State private var dropTarget: TabStripDropTarget?
    @Environment(\.chromeMetrics) private var metrics
    @Environment(\.colorTone) private var colorTone

    public init(
        items: [TabStripItem], activeID: UUID, canGoBack: Bool, canGoForward: Bool,
        onSelect: @escaping (UUID) -> Void, onClose: @escaping (UUID) -> Void, onNew: @escaping () -> Void,
        onBack: @escaping () -> Void, onForward: @escaping () -> Void, showsHistory: Bool = true,
        drop: TabStripDrop? = nil,
        @ViewBuilder leading: () -> Leading = { EmptyView() }
    ) {
        self.showsHistory = showsHistory
        self.items = items
        self.activeID = activeID
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.onSelect = onSelect
        self.onClose = onClose
        self.onNew = onNew
        self.onBack = onBack
        self.onForward = onForward
        self.drop = drop
        self.leading = leading()
    }

    public static var height: CGFloat { Size.tabBar }

    public var body: some View {
        HStack(spacing: Spacing.s1) {
            leading
            // A native toolbar puts back/forward in their own glass group (showsHistory: false).
            if showsHistory {
                SidebarIconButton("app:chrome.back", symbol: .caretLeft, action: onBack)
                    .disabled(!canGoBack)
                    .opacity(canGoBack ? 1 : 0.4)
                SidebarIconButton("app:chrome.forward", symbol: .caretRight, action: onForward)
                    .disabled(!canGoForward)
                    .opacity(canGoForward ? 1 : 0.4)
            }
            tabs
            if showsHistory { Spacer(minLength: 24) }
        }
        .padding(.horizontal, Spacing.s2)
        .frame(height: metrics.barHeight)
    }

    /// The tabs and "+", one drop area: a page lands between tabs or on one.
    private var tabs: some View {
        HStack(spacing: Spacing.s1) {
            HStack(spacing: Spacing.s0_5) {
                ForEach(items) { item in
                    TabButton(
                        item: item, isActive: item.id == activeID, canClose: items.count > 1,
                        isDropTarget: dropTarget == .onto(item.id),
                        onSelect: { onSelect(item.id) }, onClose: { onClose(item.id) }
                    )
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .named(tabStripSpace))
                    } action: {
                        frames[item.id] = $0
                    }
                }
            }
            SidebarIconButton("app:tabs.new", symbol: .plus, action: onNew)
        }
        .coordinateSpace(name: tabStripSpace)
        .overlay {
            // The line sits on the strip's own middle (the toolbar bar is taller than the tabs).
            GeometryReader { strip in
                if case .between(let index) = dropTarget, let x = gapX(before: index) {
                    colorTone.fill.frame(width: 2, height: 22).clipShape(.capsule)
                        .position(x: x, y: strip.size.height / 2)
                }
            }
            .allowsHitTesting(false)
        }
        .modifier(DropArea(drop: drop, target: target(at:), indicator: $dropTarget))
        // A drop that changed the tabs is over, whatever the drag session still reports.
        .onChange(of: items) { _, _ in dropTarget = nil }
    }

    /// The gap before the tab at `index` (after the last one for `items.count`), in the strip's space.
    private func gapX(before index: Int) -> CGFloat? {
        if index < items.count, let frame = frames[items[index].id] { return frame.minX - Spacing.s0_5 / 2 }
        if index == items.count, let last = items.last, let frame = frames[last.id] { return frame.maxX + Spacing.s0_5 / 2 }
        return nil
    }

    /// Safari's rule: the middle of a tab is that tab, its edges and the gaps are "between".
    private func target(at point: CGPoint) -> TabStripDropTarget? {
        for (index, item) in items.enumerated() {
            guard let frame = frames[item.id] else { continue }
            if point.x < frame.minX { return .between(index) }
            if point.x <= frame.maxX {
                let edge = frame.width / 4
                if point.x < frame.minX + edge { return .between(index) }
                if point.x > frame.maxX - edge { return .between(index + 1) }
                return .onto(item.id)
            }
        }
        return items.isEmpty ? nil : .between(items.count)
    }
}

/// The coordinate space the tab frames and the drop point share.
nonisolated private let tabStripSpace = "hk-tab-strip"

/// Applies the strip's drop handling when there is any.
private struct DropArea: ViewModifier {
    let drop: TabStripDrop?
    let target: (CGPoint) -> TabStripDropTarget?
    @Binding var indicator: TabStripDropTarget?

    func body(content: Content) -> some View {
        if let drop {
            content.onDrop(of: drop.types, delegate: TabStripDropDelegate(drop: drop, target: target, indicator: $indicator))
        } else {
            content
        }
    }
}

private struct TabStripDropDelegate: DropDelegate {
    let drop: TabStripDrop
    let target: (CGPoint) -> TabStripDropTarget?
    @Binding var indicator: TabStripDropTarget?

    func validateDrop(info: DropInfo) -> Bool { drop.accepts() }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Updates can still arrive after the drop (the session winding down): nothing to show then.
        let next = drop.accepts() ? target(info.location) : nil
        if indicator != next { indicator = next }
        return DropProposal(operation: next == nil ? .forbidden : .copy)
    }

    func dropExited(info: DropInfo) { indicator = nil }

    func performDrop(info: DropInfo) -> Bool {
        indicator = nil
        guard let target = target(info.location) else { return false }
        return drop.perform(target)
    }
}

private struct TabButton: View {
    let item: TabStripItem
    let isActive: Bool
    let canClose: Bool
    var isDropTarget = false
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false
    @Environment(\.colorTone) private var colorTone

    var body: some View {
        HStack(spacing: Spacing.s1_5) {
            if let symbol = item.symbol {
                IconView(symbol, size: TextSize.sm.rawValue).foregroundStyle(Theme.subtleForeground)
            } else {
                PageIcon(item.icon, size: 15)
            }
            Text(item.title.isEmpty ? String(localized: "app:page.untitled") : item.title)
                .font(.hk(.md, isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Theme.foreground : Theme.subtleForeground)
                .lineLimit(1)
            Spacer(minLength: 0)
            if canClose && (hovering || isActive) {
                Button(action: onClose) {
                    IconView(.x, size: TextSize.xs.rawValue)
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 18, height: 18)
                        .contentShape(.circle)
                }
                .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.full))
                .accessibilityLabel("app:tabs.close")
            }
        }
        .padding(.horizontal, Spacing.s3)
        // The capsule's glass shading is heavier along its bottom edge, so content centred on the frame reads a
        // touch high; a point down lands it on the capsule's visual middle (measured on a 2x capture).
        .offset(y: Spacing.s0_5 / 2)
        .frame(minWidth: 60, idealWidth: 200, maxWidth: 220, minHeight: 30, maxHeight: 30)
        // Capsules inside the toolbar's glass capsule, like a segmented control (App Store's sidebar).
        .background(
            Capsule()
                .fill(isDropTarget ? colorTone.selectionFill : isActive ? Theme.background : hovering ? Theme.accent : .clear)
                .shadow(color: isActive ? .black.opacity(0.08) : .clear, radius: 1, y: 0.5)
        )
        .animation(Motion.easeOut(), value: isDropTarget)
        .contentShape(.capsule)
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "app:tabs.close", onClose)
        .accessibilityIdentifier("tab-\(item.title)")
    }
}

#Preview {
    let a = UUID()
    let b = UUID()
    TabStrip(
        items: [TabStripItem(id: a, title: "Welcome to Hikki", icon: "👋"), TabStripItem(id: b, title: "", symbol: .house)],
        activeID: a, canGoBack: true, canGoForward: false,
        onSelect: { _ in }, onClose: { _ in }, onNew: {}, onBack: {}, onForward: {},
        drop: TabStripDrop(types: [.plainText], accepts: { true }, perform: { _ in true })
    )
    .background(Theme.sidebar)
    .frame(width: 700)
}
