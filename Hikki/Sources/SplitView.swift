import HikkiCore
import HikkiUI
import SwiftUI
import UniformTypeIdentifiers

enum SplitPreferences {
    /// The left side's share of the width, remembered.
    static let fractionKey = "split.fraction"
}

/// The window's one or two sides, split by a divider that drags. Without a split it is just the leading side (the
/// focused tab); split, the two tabs of the split side by side — equals, each a `PaneColumn` with its own bar, tools and
/// panel. A click or a tap in a side gives it the focus (`Navigator.focus`). Mac and iPad.
struct SplitDetail<Leading: View, Trailing: View>: View {
    let navigator: Navigator
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    @AppStorage(SplitPreferences.fractionKey) private var fraction = 0.5
    @State private var dragStart: Double?
    /// Each side's frame in the window, to tell which side a click or tap lands in.
    @State private var frames: [PaneSide: CGRect] = [:]

    var body: some View {
        // One structure split or not, so the leading side keeps its identity: built anew, it made its editor view again
        // around the window's one web view, and taking the old view away took the web view with it (a blank side as the
        // window split).
        GeometryReader { proxy in
            let width = proxy.size.width
            // The sides share what the hairline leaves (half and half is the same width on each side); the grip
            // takes no room of its own, so each side's page — a cover too — runs right up to the line.
            let left =
                navigator.isSplit
                ? SplitGeometry.leftWidth(total: width, fraction: fraction, grip: Spacing.px, minimum: Size.splitMin)
                : width
            HStack(spacing: Spacing.s0) {
                leading
                    .modifier(EdgeDrop(navigator: navigator))
                    .frame(width: left)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { frames[.leading] = $0 })
                if navigator.isSplit {
                    Theme.border
                        .frame(width: Spacing.px)
                        .frame(maxHeight: .infinity)
                        .ignoresSafeArea(edges: .top)
                    trailing
                        .frame(maxWidth: .infinity)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { frames[.trailing] = $0 })
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topLeading) {
                if navigator.isSplit {
                    grip(width: width)
                        .offset(x: left + Spacing.px / 2 - Size.splitGrip / 2)
                }
            }
        }
        .background {
            // Before the click reaches the page (or a list, a PDF) under it: so a link clicked in a side opens there.
            PointerDownMonitor { point in
                guard navigator.isSplit, let side = frames.first(where: { $0.value.contains(point) })?.key else { return }
                navigator.focus(side)
            }
        }
    }

    /// The grip over the hairline, a native view so it gets the clicks and drags over the web views beside it (a
    /// SwiftUI view there didn't: AppKit gives them to the web view under it). Dragging moves the boundary (each side
    /// keeps at least `Size.splitMin`); a double-click (double-tap) puts it back in the middle.
    private func grip(width: CGFloat) -> some View {
        SplitGrip(
            onDrag: { translation in
                let start = dragStart ?? fraction
                dragStart = start
                fraction = SplitGeometry.dragged(from: start, by: translation, total: width, grip: Spacing.px)
            },
            onEnd: { dragStart = nil },
            onReset: { withAnimation(Motion.easeOut()) { fraction = 0.5 } }
        )
        .frame(width: Size.splitGrip)
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("split-divider")
    }
}

/// A side of the window: while split, its bar (what it shows, its page's tools, swap, close) over what it shows; then
/// its panel (outline, comments, AI) when open. Both sides are this one view, so they can't drift apart. Not split, the
/// leading side is just the page and its panel (the page's tools are in the window toolbar).
struct PaneColumn<Content: View, Panel: View>: View {
    @Environment(AppModel.self) private var model
    let side: PaneSide
    let navigator: Navigator
    /// The side's editor (nil until its first page): the page's ⋯ menu finds in it.
    let editor: EditorController?
    /// Mac / iPad: the panel sits beside the page (an iPhone shows it as a sheet).
    let wide: Bool
    @ViewBuilder let content: Content
    /// The side's panel, given the most it may take (split, a little under half the side).
    @ViewBuilder let panel: (CGFloat?) -> Panel
    @State private var dropTargeted = false
    @State private var width: CGFloat = 0

    /// A page is held over an edge whose drop shows it on the trailing side (the leading page's, or its own).
    private var heldOverEdge: Bool { navigator.splitDropHover || navigator.splitDropHere }

    private var pane: Pane? { navigator.pane(side) }

    var body: some View {
        VStack(spacing: Spacing.s0) {
            if navigator.isSplit {
                // Across the whole side, its panel included: the side's tools stay together at its top right.
                PaneBar(side: side, navigator: navigator, editor: editor)
                // The bar's rule meets the hairline between the sides.
                Theme.border.frame(height: Spacing.px)
            }
            HStack(spacing: Spacing.s0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        // A page held over the side (the trailing one also when it is over the leading page's right
                        // edge): dropping it shows it here. An empty side's picker has a drop area of its own.
                        if navigator.isSplit && (dropTargeted && pane?.route != .splitPicker || side == .trailing && heldOverEdge) {
                            DropTargetArea(
                                navigator.splitDropHover ? "app:split.drop.replace" : "app:split.drop.here", isTargeted: true
                            )
                            .padding(Spacing.s2)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        // The page's save indicator (the iPhone's foot is its floating bar's). It reads the tracker
                        // itself, so a save redraws only the chip.
                        if wide, let pageID = pane?.route.pageID {
                            SyncIndicator(pageID: pageID, tracker: model.pageSync)
                                .padding(Spacing.s3)
                                .ignoresSafeArea(.keyboard)
                        }
                    }
                if wide && navigator.inspector(side).isShowing && pane?.route.pageID != nil {
                    panel(navigator.isSplit ? (width * 0.45).rounded() : nil)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(Theme.background)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width = $0 })
        .modifier(PaneDrop(navigator: navigator, side: side, targeted: $dropTargeted))
        .animation(Motion.easeOut(), value: dropTargeted)
        .animation(Motion.easeOut(), value: navigator.splitDropHover)
        .animation(Motion.easeOut(), value: navigator.splitDropHere)
        .animation(Motion.easeOut(), value: navigator.inspector(side))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(side == .trailing ? "split-pane" : "pane-leading")
    }
}

/// A page dragged from the sidebar or a tab onto a side shows there, whatever it showed. (Over a side's page the editor
/// takes the drag: the leading page's right edge replaces the trailing side, the rest makes a link.) Only while split —
/// checked when it lands, not by applying the drop conditionally: that changed the side's identity as the window split,
/// and SwiftUI rebuilt the leading page's view, taking the window's one web view with the old one (a blank page).
private struct PaneDrop: ViewModifier {
    let navigator: Navigator
    let side: PaneSide
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        content.onDrop(of: PageDrop.types, isTargeted: $targeted) { providers in
            guard navigator.isSplit else { return false }
            return PageDrop.page(from: providers, navigator: navigator) { id in navigator.show(.page(id), in: side) }
        }
    }
}

/// A side's bar while split: what it shows (a chooser of recent pages, or the picker), then its page's tools — lock,
/// favorite, ⋯, the panel's outline / comments / AI — then swap sides and close this side. The focused side's title is in
/// full colour, the other's quieter (the tab strip marks it too).
private struct PaneBar: View {
    @Environment(AppModel.self) private var model
    let side: PaneSide
    let navigator: Navigator
    let editor: EditorController?

    private var pane: Pane? { navigator.pane(side) }
    private var focused: Bool { navigator.focusedSide == side }

    var body: some View {
        HStack(spacing: Spacing.s1) {
            if let pane, pane.route != .splitPicker {
                chooser(pane.route)
            } else {
                Text("app:split.pickTitle")
                    .font(.hk(.md, .medium))
                    .foregroundStyle(Theme.subtleForeground)
                    .padding(.leading, Spacing.s1_5)
            }
            Spacer(minLength: Spacing.s2)
            if let id = pane?.route.pageID, let page = model.tree.page(id) {
                if page.isLocked { LockIndicator(page: page) }
                FavoriteButton(page: page)
                PageMoreMenu(page: page, navigator: navigator, editor: editor)
                Theme.border.frame(width: Spacing.px, height: Size.iconButton / 2).padding(.horizontal, Spacing.s1)
                panelToggle(.outline, "app:inspector.outline", icon: .listBullets, id: "inspector-toggle")
                panelToggle(.comments, "app:inspector.comments", icon: .chatTeardropText, id: "comments-toggle")
                aiToggle
                Theme.border.frame(width: Spacing.px, height: Size.iconButton / 2).padding(.horizontal, Spacing.s1)
            }
            BarIconButton("app:split.swap", symbol: .arrowsLeftRight) {
                withAnimation(Motion.easeOut()) { navigator.swapSides() }
            }
            .accessibilityIdentifier("split-swap-\(side.rawValue)")
            BarIconButton("app:split.closeSide", symbol: .x) {
                withAnimation(Motion.easeOut()) { navigator.closePane(side) }
            }
            .accessibilityIdentifier("split-close-\(side.rawValue)")
        }
        .padding(.horizontal, Spacing.s2)
        .frame(height: Size.pageBar)
        // A click on the bar's empty part focuses the side too (on iPad the touch watcher covers it; this is the Mac's
        // fallback for a bar over no page).
        .contentShape(.rect)
        .onTapGesture { navigator.focus(side) }
        // A container, so each control keeps its own identifier (on iOS the bar's own took them all over).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane-bar-\(side.rawValue)")
    }

    /// What the side shows, as a chooser (⌃⌄, a pop-up button's mark): recent pages to switch to, or the whole picker.
    private func chooser(_ route: Route) -> some View {
        Menu {
            ForEach(model.tree.recent(limit: 8)) { page in
                Button {
                    navigator.show(.page(page.id), in: side)
                } label: {
                    Text(verbatim: "\(page.icon.map { $0 + "  " } ?? "")\(PaneBar.title(page))")
                }
            }
            Divider()
            Button("app:split.more") { navigator.showSplitPicker(in: side) }
                .accessibilityIdentifier("split-more")
        } label: {
            HStack(spacing: Spacing.s2) {
                current(route)
                IconView(.caretUpDown, size: TextSize.xs.rawValue).foregroundStyle(Theme.mutedForeground)
            }
            .padding(.horizontal, Spacing.s1_5)
            .padding(.vertical, Spacing.s1)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md))
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help("app:split.change")
        .accessibilityIdentifier("split-change-\(side.rawValue)")
    }

    @ViewBuilder private func current(_ route: Route) -> some View {
        let ink = focused ? Theme.foreground : Theme.mutedForeground
        switch route {
        case .page(let id):
            PageIcon(model.tree.page(id)?.icon, size: 16)
            Text(Self.title(model.tree.page(id))).font(.hk(.md, .medium)).foregroundStyle(ink).lineLimit(1)
        case .file(_, let label):
            IconView(.fileText, size: TextSize.sm.rawValue).foregroundStyle(Theme.subtleForeground)
            Text(label).font(.hk(.md, .medium)).foregroundStyle(ink).lineLimit(1)
        case .home:
            IconView(.house, size: TextSize.sm.rawValue).foregroundStyle(Theme.subtleForeground)
            Text("app:nav.home").font(.hk(.md, .medium)).foregroundStyle(ink).lineLimit(1)
        case .trash:
            IconView(.trash, size: TextSize.sm.rawValue).foregroundStyle(Theme.subtleForeground)
            Text("app:nav.trash").font(.hk(.md, .medium)).foregroundStyle(ink).lineLimit(1)
        case .splitPicker:
            EmptyView()
        }
    }

    /// One of the panel's views: on while the side's panel shows it; pressed, it opens the panel there or closes it.
    private func panelToggle(_ mode: InspectorMode, _ title: LocalizedStringKey, icon: Icon, id: String) -> some View {
        let on = navigator.inspector(side).isShowing && navigator.inspector(side).mode == mode
        return ToolbarIconButton(title, symbol: icon, isActive: on) { navigator.toggleInspector(mode, side: side) }
            .accessibilityIdentifier("\(id)-\(side.rawValue)")
    }

    private var aiToggle: some View {
        let on = navigator.inspector(side).isShowing && navigator.inspector(side).mode == .ai
        return Button {
            navigator.toggleInspector(.ai, side: side)
        } label: {
            AIGlyph(tinted: on)
                .frame(width: Size.toolbarButtonWidth, height: Size.toolbarButtonHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("app:inspector.ai")
        .accessibilityLabel("app:inspector.ai")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("ai-toggle-\(side.rawValue)")
    }

    static func title(_ page: PageSummary?) -> String {
        guard let page, !page.title.isEmpty else { return String(localized: "app:page.untitled") }
        return page.title
    }
}

/// What an empty side offers: the PDFs at hand (attached to the other side's page, open in tabs) and recent pages. A page
/// dragged here shows here.
struct SplitPicker: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    /// The side it fills; the other side's page lends its PDFs.
    let side: PaneSide
    @State private var dropTargeted = false
    @State private var attachedPDFs: [AssetReference] = []

    /// The page on the other side.
    private var otherRoute: Route? { navigator.pane(side == .leading ? .trailing : .leading)?.route }

    var body: some View {
        // The left page too: it may be read on the right while written on the left.
        let recent = model.tree.recent(limit: 12)
        let pdfs = self.pdfs
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                // Pages come here by drag too: say so where the eye starts.
                DropTargetArea("app:split.dropArea", icon: .trayArrowDown, isTargeted: dropTargeted)
                    .frame(height: Size.splitDropArea)
                    .padding(.bottom, Spacing.s2)
                    .accessibilityIdentifier("split-drop-area")
                if !pdfs.isEmpty {
                    header("app:split.pdfs")
                    ForEach(pdfs, id: \.name) { pdf in
                        row(title: pdf.label, icon: AnyView(IconView(.fileText, size: TextSize.base.rawValue))) {
                            navigator.show(.file(name: pdf.name, label: pdf.label), in: side)
                        }
                        .accessibilityIdentifier("split-pick-\(pdf.label)")
                    }
                }
                header("app:split.recent")
                if recent.isEmpty && pdfs.isEmpty {
                    Text("app:split.empty").font(.hk(.md)).foregroundStyle(Theme.mutedForeground).padding(Spacing.s2)
                }
                ForEach(recent) { page in
                    row(title: PaneBar.title(page), icon: AnyView(PageIcon(page.icon, size: Size.pageIcon))) {
                        navigator.show(.page(page.id), in: side)
                    }
                    .accessibilityIdentifier("split-pick-\(PaneBar.title(page))")
                }
            }
            .padding(Spacing.s3)
        }
        .onDrop(of: PageDrop.types, isTargeted: $dropTargeted) { providers in
            PageDrop.page(from: providers, navigator: navigator) { id in navigator.show(.page(id), in: side) }
        }
        .task(id: otherRoute) {
            guard let id = otherRoute?.pageID, let record = try? model.store.document(id: id) else {
                attachedPDFs = []
                return
            }
            attachedPDFs = record.assetReferences.filter { ($0.name as NSString).pathExtension.lowercased() == "pdf" }
        }
    }

    /// PDFs attached to the other side's page, then PDFs open in tabs — each once.
    private var pdfs: [(name: String, label: String)] {
        var seen = Set<String>()
        var out: [(name: String, label: String)] = []
        for reference in attachedPDFs where seen.insert(reference.name).inserted {
            out.append((reference.name, reference.label ?? reference.name))
        }
        for tab in navigator.tabs.tabs {
            if case .file(let name, let label) = tab.route, otherRoute != tab.route, seen.insert(name).inserted {
                out.append((name, label))
            }
        }
        return out
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.hk(.xs, .medium))
            .foregroundStyle(Theme.mutedForeground)
            .padding(.horizontal, Spacing.s2)
            .padding(.top, Spacing.s3)
    }

    private func row(title: String, icon: AnyView, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.s2) {
                icon.foregroundStyle(Theme.subtleForeground)
                Text(title).font(.hk(.md)).foregroundStyle(Theme.foreground).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s2)
            .padding(.vertical, Spacing.s1_5)
            .contentShape(.rect)
        }
        .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md))
    }
}

/// Pages dropped on native views (the split pane, the right edge of Home or a PDF): a sidebar row's drag says which
/// page it is (`Navigator.draggingPageID`); a tab's carries the page's link.
enum PageDrop {
    static let types: [UTType] = [.url, .plainText]

    /// Calls `open` with the dropped page (now, or once the link has loaded); false when nothing here is a page.
    static func page(
        from providers: [NSItemProvider], navigator: Navigator, open: @escaping @MainActor @Sendable (String) -> Void
    ) -> Bool {
        if let id = navigator.draggingPageID {
            navigator.draggingPageID = nil
            open(id)
            return true
        }
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) || $0.canLoadObject(ofClass: String.self) })
        else { return false }
        let deliver: @Sendable (URL?) -> Void = { url in
            guard let url, let id = PageLink.pageID(from: url) else { return }
            Task { @MainActor in open(id) }
        }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in deliver(url) }
        } else {
            _ = provider.loadObject(ofClass: String.self) { text, _ in deliver(text.flatMap { URL(string: $0) }) }
        }
        return true
    }
}

/// The right edge of what the left side shows when it isn't a page (Home, Trash, a PDF): a page dropped there opens
/// in the pane on the right, and while one is over it the right half shows where. (A page's editor has its own edge,
/// `apps/editor/src/extensions/split-drop.ts`.) Mac and the larger iPads only.
private struct EdgeDrop: ViewModifier {
    let navigator: Navigator
    @State private var showing = false
    /// Only where the window may split (`DeviceRules.allowsSplit`; ContentView sets it).
    @Environment(\.splitAvailable) private var available

    func body(content: Content) -> some View {
        if available {
            GeometryReader { proxy in
                content
                    .onDrop(of: PageDrop.types, delegate: Delegate(width: proxy.size.width, navigator: navigator, showing: $showing))
                    .overlay(alignment: .trailing) {
                        // Split already: the right side outlines itself whole (`Navigator.splitDropHover`).
                        if showing && !navigator.isSplit {
                            // Opens beside it, or — split already — replaces what the right side shows.
                            DropTargetArea(navigator.isSplit ? "app:split.drop.replace" : "app:split.drop.open", isTargeted: true)
                                .background(Theme.background.opacity(0.6), in: .rect(cornerRadius: Radius.lg))
                                .frame(width: proxy.size.width / 2)
                                .padding(Spacing.s2)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .animation(Motion.easeOut(), value: showing)
            }
        } else {
            content
        }
    }

    private struct Delegate: DropDelegate {
        let width: CGFloat
        let navigator: Navigator
        @Binding var showing: Bool

        /// The right quarter, within 96…240 points (as in the editor).
        private func inZone(_ info: DropInfo) -> Bool {
            info.location.x >= width - max(96, min(240, width / 4))
        }

        func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: PageDrop.types) }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            let inside = inZone(info)
            if showing != inside { showing = inside }
            if navigator.isSplit, navigator.splitDropHover != inside { navigator.splitDropHover = inside }
            return DropProposal(operation: inside ? .copy : .cancel)
        }

        func dropExited(info: DropInfo) {
            showing = false
            navigator.splitDropHover = false
        }

        func performDrop(info: DropInfo) -> Bool {
            showing = false
            navigator.splitDropHover = false
            guard inZone(info) else { return false }
            return PageDrop.page(from: info.itemProviders(for: PageDrop.types), navigator: navigator) { id in
                navigator.openBeside(.page(id))
            }
        }
    }
}

/// Tells where in the window each click or touch starts, before the view under it gets it (a page, a list, a PDF):
/// split view gives that side the focus first, so a link clicked there opens there. It never takes the click itself.
private struct PointerDownMonitor {
    /// The point, in the window's global SwiftUI space (`.global`).
    let onDown: (CGPoint) -> Void
}

#if os(macOS)
    extension PointerDownMonitor: NSViewRepresentable {
        func makeNSView(context: Context) -> MonitorView {
            let view = MonitorView()
            view.onDown = onDown
            return view
        }

        func updateNSView(_ view: MonitorView, context: Context) { view.onDown = onDown }

        static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

        final class MonitorView: NSView {
            var onDown: ((CGPoint) -> Void)?
            private var monitor: Any?

            override func hitTest(_ point: NSPoint) -> NSView? { nil }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                stop()
                guard window != nil else { return }
                // A local monitor sees the event before the window sends it to the view under it.
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
                    [weak self] event in
                    MainActor.assumeIsolated { self?.handle(event) }
                    return event
                }
            }

            private func handle(_ event: NSEvent) {
                guard let window, event.window === window, let root = window.contentView else { return }
                let point = root.convert(event.locationInWindow, from: nil)
                onDown?(root.isFlipped ? point : CGPoint(x: point.x, y: root.bounds.height - point.y))
            }

            func stop() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
        }
    }
#else
    extension PointerDownMonitor: UIViewRepresentable {
        func makeUIView(context: Context) -> ProbeView {
            let view = ProbeView()
            view.recognizer.onDown = onDown
            return view
        }

        func updateUIView(_ view: ProbeView, context: Context) { view.recognizer.onDown = onDown }

        /// Puts the touch watcher on the window (a view of its own would only see touches on itself).
        final class ProbeView: UIView {
            let recognizer = TouchDownRecognizer()

            override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                recognizer.view?.removeGestureRecognizer(recognizer)
                window?.addGestureRecognizer(recognizer)
            }
        }

        /// Reports a touch as it begins, then fails at once: every other gesture and control goes on as if it weren't
        /// there.
        final class TouchDownRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
            var onDown: ((CGPoint) -> Void)?

            init() {
                super.init(target: nil, action: nil)
                cancelsTouchesInView = false
                delaysTouchesBegan = false
                delaysTouchesEnded = false
                delegate = self
            }

            override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
                if let touch = touches.first, let window = view { onDown?(touch.location(in: window)) }
                state = .failed
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
            ) -> Bool { true }
        }
    }
#endif

/// The split view's grip: a native view on top of the web views, so a press over the hairline is the grip's and not
/// the page's. It reports the drag's horizontal travel, its end, and a double-click / double-tap.
struct SplitGrip {
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void
}

#if os(macOS)
    extension SplitGrip: NSViewRepresentable {
        func makeNSView(context: Context) -> GripView { update(GripView()) }
        func updateNSView(_ view: GripView, context: Context) { _ = update(view) }

        private func update(_ view: GripView) -> GripView {
            view.onDrag = onDrag
            view.onEnd = onEnd
            view.onReset = onReset
            return view
        }

        final class GripView: NSView {
            var onDrag: ((CGFloat) -> Void)?
            var onEnd: (() -> Void)?
            var onReset: (() -> Void)?
            private var start: CGFloat?

            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

            override func mouseDown(with event: NSEvent) {
                if event.clickCount == 2 {
                    onReset?()
                    return
                }
                start = event.locationInWindow.x
            }

            override func mouseDragged(with event: NSEvent) {
                guard let start else { return }
                onDrag?(event.locationInWindow.x - start)
            }

            override func mouseUp(with event: NSEvent) {
                guard start != nil else { return }
                start = nil
                onEnd?()
            }

            // The resize cursor over the whole grip; set again as the pointer moves, since the web view beside it
            // sets its own cursor on every move.
            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                for area in trackingAreas { removeTrackingArea(area) }
                addTrackingArea(
                    NSTrackingArea(
                        rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .cursorUpdate, .mouseMoved, .mouseEnteredAndExited],
                        owner: self))
            }

            override func cursorUpdate(with event: NSEvent) { NSCursor.columnResize.set() }
            override func mouseEntered(with event: NSEvent) { NSCursor.columnResize.set() }
            override func mouseMoved(with event: NSEvent) { NSCursor.columnResize.set() }
        }
    }
#else
    extension SplitGrip: UIViewRepresentable {
        func makeUIView(context: Context) -> GripView { update(GripView()) }
        func updateUIView(_ view: GripView, context: Context) { _ = update(view) }

        private func update(_ view: GripView) -> GripView {
            view.onDrag = onDrag
            view.onEnd = onEnd
            view.onReset = onReset
            return view
        }

        final class GripView: UIView, UIPointerInteractionDelegate {
            var onDrag: ((CGFloat) -> Void)?
            var onEnd: (() -> Void)?
            var onReset: (() -> Void)?

            override init(frame: CGRect) {
                super.init(frame: frame)
                addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan)))
                let doubleTap = UITapGestureRecognizer(target: self, action: #selector(reset))
                doubleTap.numberOfTapsRequired = 2
                addGestureRecognizer(doubleTap)
                addInteraction(UIPointerInteraction(delegate: self))
            }

            required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

            /// Where the finger came down: the boundary follows it from there (a pan's own translation starts only
            /// once it is recognized, a few points in).
            private var start: CGFloat?

            override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
                start = touches.first?.location(in: window).x
                super.touchesBegan(touches, with: event)
            }

            @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
                let travel = start.map { recognizer.location(in: window).x - $0 } ?? recognizer.translation(in: window).x
                switch recognizer.state {
                case .changed: onDrag?(travel)
                case .ended:
                    // The last of a quick drag comes with its end.
                    onDrag?(travel)
                    onEnd?()
                case .cancelled, .failed: onEnd?()
                default: break
                }
            }

            @objc private func reset() { onReset?() }

            // A trackpad's pointer becomes a thin bar over the grip, as over a column edge.
            func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
                UIPointerStyle(shape: .verticalBeam(length: Size.splitGrip * 2), constrainedAxes: .vertical)
            }
        }
    }
#endif
