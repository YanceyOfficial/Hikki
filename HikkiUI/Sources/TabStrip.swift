import SwiftUI
import UniformTypeIdentifiers

/// One tab in a `TabStrip`.
public struct TabStripItem: Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var icon: String?
    public var symbol: Icon?
    /// This tab and the next are shown side by side (split view): the strip draws the two as one joined tab, the
    /// active half marked.
    public var joinedToNext: Bool

    public init(id: UUID, title: String, icon: String? = nil, symbol: Icon? = nil, joinedToNext: Bool = false) {
        self.id = id
        self.title = title
        self.icon = icon
        self.symbol = symbol
        self.joinedToNext = joinedToNext
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

extension UTType {
    /// What a tab dragged along a `TabStrip` carries besides its page's link: its id, to this process only — the strip
    /// reorders by it (declared in the app's Info.plist, `UTExportedTypeDeclarations`).
    nonisolated static let hikkiTab = UTType(exportedAs: "app.yancey.hikki.tab", conformingTo: .data)
}

/// A command in a tab's context menu (Chrome's tab menu).
public enum TabStripCommand: String, CaseIterable, Hashable, Sendable {
    case newToRight, openInSplit, swapSides, separate, duplicate, moveToNewWindow, copyLink, revealInSidebar, close,
        closeOthers, closeToRight, closeAll

    /// The command's string key: its title for SwiftUI, and as words for an AppKit menu.
    var key: String {
        switch self {
        case .newToRight: "app:tabs.newToRight"
        case .openInSplit: "app:split.openPage"
        case .swapSides: "app:split.swap"
        case .separate: "app:split.separate"
        case .duplicate: "app:tabs.duplicate"
        case .moveToNewWindow: "app:tabs.moveToNewWindow"
        case .copyLink: "app:tabs.copyLink"
        case .revealInSidebar: "app:tabs.revealInSidebar"
        case .close: "app:tabs.close"
        case .closeOthers: "app:tabs.closeOthers"
        case .closeToRight: "app:tabs.closeToRight"
        case .closeAll: "app:tabs.closeAll"
        }
    }

    var title: LocalizedStringKey { LocalizedStringKey(key) }

    var localizedTitle: String { String(localized: String.LocalizationValue(key)) }

    var icon: Icon {
        switch self {
        case .newToRight: .browsers
        case .openInSplit: .squareSplitHorizontal
        case .swapSides: .arrowsLeftRight
        case .separate: .square
        case .duplicate: .copy
        case .moveToNewWindow: .appWindow
        case .copyLink: .link
        case .revealInSidebar: .sidebarSimple
        case .close: .x
        case .closeOthers: .xSquare
        case .closeToRight: .arrowLineRight
        case .closeAll: .xCircle
        }
    }
}

/// A tab's context menu: which commands a tab offers, in sections (the caller knows what its tab shows and what the
/// window can do), and what running one means. The strip greys out the close commands that would do nothing.
public struct TabStripMenu {
    public var commands: (UUID) -> [[TabStripCommand]]
    public var perform: (TabStripCommand, UUID) -> Void

    public init(commands: @escaping (UUID) -> [[TabStripCommand]], perform: @escaping (TabStripCommand, UUID) -> Void) {
        self.commands = commands
        self.perform = perform
    }
}

/// Browser-style tab bar (Notion's top row): back/forward, tabs that shrink to fit, close on hover, "+".
/// Purely presentational — all state lives with the caller. With `drop`, a page dragged over it shows a
/// line between tabs or a tint on one (Safari's tab bar), and the caller gets where it landed. With `onMove`, a tab
/// dragged along it shows a line in the gap it would go to (Chrome's reordering), and the caller moves it there — the
/// index is the gap before that tab (`items.count`: after the last one); a split's two tabs move together.
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
    private let dragItem: ((UUID) -> NSItemProvider?)?
    private let menu: TabStripMenu?
    private let onMove: ((UUID, Int) -> Void)?
    @State private var frames: [UUID: CGRect] = [:]
    @State private var dropTarget: TabStripDropTarget?
    /// The tab whose drag started last (its drag carries `UTType.hikkiTab`, which says a drop is one).
    @State private var movingTab: UUID?
    /// Where along the moving tab it was grabbed (from the drag's first update), so its box follows the pointer.
    @State private var grabOffset: CGFloat?
    @Environment(\.colorTone) private var colorTone

    public init(
        items: [TabStripItem], activeID: UUID, canGoBack: Bool, canGoForward: Bool,
        onSelect: @escaping (UUID) -> Void, onClose: @escaping (UUID) -> Void, onNew: @escaping () -> Void,
        onBack: @escaping () -> Void, onForward: @escaping () -> Void, showsHistory: Bool = true,
        drop: TabStripDrop? = nil, dragItem: ((UUID) -> NSItemProvider?)? = nil, menu: TabStripMenu? = nil,
        onMove: ((UUID, Int) -> Void)? = nil, @ViewBuilder leading: () -> Leading = { EmptyView() }
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
        self.dragItem = dragItem
        self.menu = menu
        self.onMove = onMove
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
        .frame(height: Size.tabBar)
    }

    /// The tabs and "+", one drop area: a page lands between tabs or on one.
    private var tabs: some View {
        HStack(spacing: Spacing.s1) {
            // Every tab is an item of this one stack, a split's two included: nested in a stack of their own the pair
            // was one item, squeezed to half a tab each while the single tabs kept theirs (ISSUE-231). A hairline
            // stands between a split's two instead of the gap; their shared capsule is drawn over the strip from
            // their frames.
            HStack(spacing: Spacing.s0) {
                ForEach(items, id: \.id) { item in
                    tab(item)
                    if item.id != items.last?.id {
                        if item.joinedToNext {
                            // A little air on both sides, so the tab's close button never touches it (ISSUE-231).
                            Theme.border.frame(width: Spacing.px, height: Spacing.s4).padding(.horizontal, Spacing.s1)
                        } else {
                            Color.clear.frame(width: Spacing.s0_5)
                        }
                    }
                }
            }
            SidebarIconButton("app:tabs.new", symbol: .plus, action: onNew)
                .toolTip(String(localized: "app:tabs.new"))
                .accessibilityIdentifier("tabs-new")
        }
        .coordinateSpace(name: tabStripSpace)
        .overlay {
            // The line sits on the strip's own middle (the toolbar bar is taller than the tabs).
            GeometryReader { strip in
                // A split's two tabs in one outlined capsule.
                ForEach(splitPairs, id: \.leading) { pair in
                    if let a = frames[pair.leading], let b = frames[pair.trailing] {
                        Capsule().strokeBorder(Theme.border, lineWidth: Spacing.px)
                            .frame(width: b.maxX - a.minX, height: a.height)
                            .position(x: (a.minX + b.maxX) / 2, y: a.midY)
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("tab-split")
                    }
                }
                if case .between(let index) = dropTarget, let x = gapX(before: index) {
                    colorTone.fill.frame(width: Spacing.s0_5, height: Size.iconButtonSm).clipShape(.capsule)
                        .position(x: x, y: strip.size.height / 2)
                }
            }
            .allowsHitTesting(false)
        }
        .modifier(
            DropArea(
                drop: drop, target: target(at:), indicator: $dropTarget,
                move: onMove.map { onMove in
                    TabMove(moving: { movingTab }, target: moveTarget(at:)) { id, index in
                        movingTab = nil
                        onMove(id, index)
                    }
                })
        )
        // In a window toolbar macOS lifts the first `.help` inside the item up to the whole item, so hovering any tab
        // showed that one. The strip says nothing itself; each tab carries an AppKit tooltip of its own (`toolTip`).
        .help(Text(verbatim: ""))
        // A drop that changed the tabs is over, whatever the drag session still reports.
        .onChange(of: items) { _, _ in dropTarget = nil }
    }

    /// The splits: each pair's leading and trailing tab.
    private var splitPairs: [(leading: UUID, trailing: UUID)] {
        zip(items, items.dropFirst()).compactMap { a, b in a.joinedToNext ? (leading: a.id, trailing: b.id) : nil }
    }

    private func tab(_ item: TabStripItem) -> some View {
        TabButton(
            item: item, isActive: item.id == activeID, canClose: items.count > 1,
            isDropTarget: dropTarget == .onto(item.id),
            dragItem: dragItem != nil || onMove != nil ? { () -> NSItemProvider? in tabDragItem(item.id) } : nil,
            onSelect: { onSelect(item.id) }, onClose: { onClose(item.id) },
            menu: menu.map { menu in { entries(menu, for: item.id) } }
        )
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(tabStripSpace))
        } action: {
            frames[item.id] = $0
        }
    }

    /// What dragging the tab `id` carries: its page's link (the caller's `dragItem`), and — where tabs reorder — its id
    /// as `UTType.hikkiTab`, which only this app understands. Visible to every process like the link: registered for
    /// this process alone, it kept the page's web view from seeing the drag as one that carries a link, so a tab
    /// dragged to the page's right edge did nothing (ISSUE-227).
    private func tabDragItem(_ id: UUID) -> NSItemProvider {
        let provider = dragItem?(id) ?? NSItemProvider()
        if onMove != nil {
            movingTab = id
            grabOffset = nil
            provider.registerDataRepresentation(forTypeIdentifier: UTType.hikkiTab.identifier, visibility: .all) {
                completion in
                completion(Data(id.uuidString.utf8), nil)
                return nil
            }
        }
        return provider
    }

    /// Where the tab being dragged would go, Chrome's way (`TabReorder`): its own box — the tab (or its split pair) as
    /// wide as it is, carried where it was grabbed — swaps with a neighbour once more than half of it lies over that
    /// neighbour. Nil where nothing would move. The grab point is read from the first update of the drag.
    private func moveTarget(at point: CGPoint) -> TabStripDropTarget? {
        guard let moving = movingTab, let at = items.firstIndex(where: { $0.id == moving }) else { return nil }
        let first = at > 0 && items[at - 1].joinedToNext ? at - 1 : at
        let last = items[first].joinedToNext ? first + 1 : first
        guard let start = frames[items[first].id]?.minX, let end = frames[items[last].id]?.maxX else { return nil }
        let offset = grabOffset ?? min(max(point.x - start, 0), end - start)
        if grabOffset == nil { grabOffset = offset }
        var tabs: [ClosedRange<Double>] = []
        var joined: [Bool] = []
        for item in items {
            guard let frame = frames[item.id] else { return nil }
            tabs.append(Double(frame.minX)...Double(frame.maxX))
            joined.append(item.joinedToNext)
        }
        let left = Double(point.x - offset)
        return TabReorder.gap(tabs: tabs, joined: joined, moving: at, box: left...(left + Double(end - start)))
            .map { .between($0) }
    }

    /// The tab's menu, its sections divided; Close / Close Other Tabs / Close All need another tab, Close Tabs to the
    /// Right one after this.
    private func entries(_ menu: TabStripMenu, for id: UUID) -> [[TabMenuEntry]] {
        menu.commands(id).map { section in
            section.map { command in
                TabMenuEntry(command: command, enabled: isAvailable(command, for: id)) { menu.perform(command, id) }
            }
        }
    }

    private func isAvailable(_ command: TabStripCommand, for id: UUID) -> Bool {
        switch command {
        case .close, .closeOthers, .closeAll: items.count > 1
        case .closeToRight: items.last?.id != id
        default: true
        }
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

/// A tab dragged along the strip: which one (the last whose drag started), where it would go, and moving it there.
private struct TabMove {
    let moving: () -> UUID?
    let target: (CGPoint) -> TabStripDropTarget?
    let perform: (UUID, Int) -> Void
}

/// Applies the strip's drop handling when there is any: pages dropped on it, tabs dragged along it.
private struct DropArea: ViewModifier {
    let drop: TabStripDrop?
    let target: (CGPoint) -> TabStripDropTarget?
    @Binding var indicator: TabStripDropTarget?
    let move: TabMove?

    func body(content: Content) -> some View {
        if drop != nil || move != nil {
            content.onDrop(
                of: (drop?.types ?? []) + (move != nil ? [.hikkiTab] : []),
                delegate: TabStripDropDelegate(drop: drop, target: target, move: move, indicator: $indicator))
        } else {
            content
        }
    }
}

private struct TabStripDropDelegate: DropDelegate {
    let drop: TabStripDrop?
    let target: (CGPoint) -> TabStripDropTarget?
    let move: TabMove?
    @Binding var indicator: TabStripDropTarget?

    /// A tab of this strip being dragged along it (a tab's drag also carries its page's link, so this comes first).
    private func isMove(_ info: DropInfo) -> Bool {
        move?.moving() != nil && info.hasItemsConforming(to: [.hikkiTab])
    }

    func validateDrop(info: DropInfo) -> Bool { isMove(info) || drop?.accepts() == true }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let move, isMove(info) {
            let next = move.target(info.location)
            if indicator != next { indicator = next }
            return DropProposal(operation: .move)
        }
        // Updates can still arrive after the drop (the session winding down): nothing to show then.
        let next = drop?.accepts() == true ? target(info.location) : nil
        if indicator != next { indicator = next }
        return DropProposal(operation: next == nil ? .forbidden : .copy)
    }

    func dropExited(info: DropInfo) { indicator = nil }

    func performDrop(info: DropInfo) -> Bool {
        indicator = nil
        if let move, isMove(info), let id = move.moving() {
            // Dropped where it already was: the drag is over all the same.
            if case .between(let index)? = move.target(info.location) { move.perform(id, index) }
            return true
        }
        guard let drop, let target = target(info.location) else { return false }
        return drop.perform(target)
    }
}

/// One command of a tab's context menu, as the tab can run it now.
private struct TabMenuEntry {
    let command: TabStripCommand
    let enabled: Bool
    let perform: () -> Void
}

private struct TabButton: View {
    let item: TabStripItem
    let isActive: Bool
    let canClose: Bool
    var isDropTarget = false
    /// What dragging the tab carries (its page's link); nil: the tab doesn't drag.
    var dragItem: (() -> NSItemProvider?)?
    let onSelect: () -> Void
    let onClose: () -> Void
    /// The tab's context menu, asked for as it opens; nil: none.
    var menu: (() -> [[TabMenuEntry]])?
    @State private var hovering = false
    @Environment(\.colorTone) private var colorTone

    var body: some View {
        HStack(spacing: Spacing.s1_5) {
            if let symbol = item.symbol {
                IconView(symbol, size: TextSize.sm.rawValue).foregroundStyle(Theme.subtleForeground)
            } else {
                PageIcon(item.icon, size: Size.pageIcon)
            }
            Text(verbatim: PageTitle.display(item.title))
                .font(.hk(.md, isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Theme.foreground : Theme.subtleForeground)
                .lineLimit(1)
            Spacer(minLength: 0)
            if canClose && (hovering || isActive) {
                // The same quiet hover as every other icon button (a rounded square, not a disc — ISSUE-231).
                Button(action: onClose) {
                    IconView(.x, size: TextSize.xs.rawValue)
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: Size.sidebarIcon, height: Size.sidebarIcon)
                        .contentShape(.rect(cornerRadius: Radius.sm))
                }
                .buttonStyle(HoverHighlightStyle())
                .accessibilityLabel("app:tabs.close")
            }
        }
        .padding(.horizontal, Spacing.s3)
        .frame(
            minWidth: Size.tabMin, idealWidth: Size.tabIdeal, maxWidth: Size.tabMax, minHeight: Size.tabHeight, maxHeight: Size.tabHeight
        )
        // Capsules inside the toolbar's glass capsule, like a segmented control (App Store's sidebar).
        .background(
            Capsule()
                .fill(isDropTarget ? colorTone.selectionFill : isActive ? Theme.background : hovering ? Theme.accent : .clear)
                .shadow(color: isActive ? .black.opacity(0.08) : .clear, radius: 1, y: 0.5)
        )
        .animation(Motion.easeOut(), value: isDropTarget)
        .contentShape(.capsule)
        .modifier(TabMenu(entries: menu))
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .modifier(TabDrag(item: dragItem))
        // The whole title, for a tab narrowed down to "N1…".
        .toolTip(PageTitle.display(item.title))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "app:tabs.close", onClose)
        .accessibilityIdentifier("tab-\(item.title)")
    }
}

/// The tab's context menu. On the Mac an AppKit menu over the tab (`ContextMenuOverlay`): in the window toolbar
/// SwiftUI's `.contextMenu` never showed, before the tab's drag or without one (ISSUE-191, ISSUE-231). Elsewhere
/// SwiftUI's own.
private struct TabMenu: ViewModifier {
    let entries: (() -> [[TabMenuEntry]])?

    func body(content: Content) -> some View {
        if let entries {
            #if os(macOS)
                content.overlay {
                    ContextMenuOverlay {
                        entries().map { section in
                            section.map { entry in
                                ContextMenuOverlay.Item(
                                    title: entry.command.localizedTitle, symbol: entry.command.icon.systemName,
                                    enabled: entry.enabled, identifier: "tab-menu-\(entry.command.rawValue)",
                                    action: entry.perform)
                            }
                        }
                    }
                }
            #else
                content.contextMenu {
                    let sections = entries()
                    ForEach(sections.indices, id: \.self) { index in
                        if index > 0 { Divider() }
                        ForEach(sections[index], id: \.command) { entry in
                            Button(action: entry.perform) { IconLabel(entry.command.title, icon: entry.command.icon) }
                                .disabled(!entry.enabled)
                                .accessibilityIdentifier("tab-menu-\(entry.command.rawValue)")
                        }
                    }
                }
            #endif
        } else {
            content
        }
    }
}

/// A tab dragged out (onto the split pane, into a page) carries its page's link.
private struct TabDrag: ViewModifier {
    let item: (() -> NSItemProvider?)?

    func body(content: Content) -> some View {
        if let item {
            content.onDrag { item() ?? NSItemProvider() }
        } else {
            content
        }
    }
}

#Preview {
    let a = UUID()
    let b = UUID()
    let c = UUID()
    let d = UUID()
    TabStrip(
        items: [
            TabStripItem(id: a, title: "Welcome to Hikki", icon: "👋"), TabStripItem(id: b, title: "", symbol: .house),
            TabStripItem(id: c, title: "初级下", icon: "🗂", joinedToNext: true), TabStripItem(id: d, title: "N4 文法", icon: "🍀"),
        ],
        activeID: d, canGoBack: true, canGoForward: false,
        onSelect: { _ in }, onClose: { _ in }, onNew: {}, onBack: {}, onForward: {},
        drop: TabStripDrop(types: [.plainText], accepts: { true }, perform: { _ in true })
    )
    .background(Theme.sidebar)
    .frame(width: 700)
}
