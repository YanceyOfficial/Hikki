import HikkiCore
import HikkiUI
import SwiftUI
import UniformTypeIdentifiers

enum SplitPreferences {
    /// The left side's share of the width, remembered.
    static let fractionKey = "split.fraction"
}

/// The current tab and, beside it, a second pane — a page (with an editor of its own) or a PDF — split by a divider
/// that drags. Without a split it is just the tab. Mac and iPad.
struct SplitDetail<Leading: View>: View {
    let navigator: Navigator
    let splitEditor: EditorController?
    @ViewBuilder let leading: Leading
    @AppStorage(SplitPreferences.fractionKey) private var fraction = 0.5
    @State private var dragStart: Double?

    var body: some View {
        if navigator.isSplit {
            GeometryReader { proxy in
                let width = proxy.size.width
                let minFraction = min(0.5, Size.splitMin / max(width, 1))
                let left = width * min(max(fraction, minFraction), 1 - minFraction)
                HStack(spacing: Spacing.s0) {
                    leading.modifier(EdgeDrop(navigator: navigator)).frame(width: left)
                    divider(width: width)
                    SplitPane(navigator: navigator, editor: splitEditor)
                        .frame(maxWidth: .infinity)
                }
            }
            .transition(.opacity)
        } else {
            leading.modifier(EdgeDrop(navigator: navigator))
        }
    }

    /// A column of its own between the sides with the hairline in its middle — a grip over the web views wouldn't get
    /// the clicks (AppKit gives them to the web view under it), so it takes real width. Dragging moves the boundary
    /// (each side keeps at least `Size.splitMin`); a double-click (double-tap) puts it back in the middle.
    private func divider(width: CGFloat) -> some View {
        Theme.border
            .frame(width: 1)
            .frame(width: Size.splitGrip)
            .frame(maxHeight: .infinity)
            .background(Theme.background)
            .ignoresSafeArea(edges: .top)
            .contentShape(.rect)
            .onTapGesture(count: 2) {
                withAnimation(Motion.easeOut()) { fraction = 0.5 }
            }
            #if os(macOS)
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
            #endif
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStart ?? fraction
                        dragStart = start
                        fraction = min(max(start + drag.translation.width / max(width, 1), 0.2), 0.8)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .accessibilityIdentifier("split-divider")
    }
}

/// The second pane: a small bar (what it shows, swap, close) over the page, the PDF, or a picker when it's empty.
private struct SplitPane: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    let editor: EditorController?
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: Spacing.s0) {
            bar
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        // A page dragged from the sidebar or a tab shows here, whatever the pane showed. (Over the pane's own page the
        // editor takes the drag: its right edge opens it here too, the rest makes a link.)
        .onDrop(of: PageDrop.types, isTargeted: $dropTargeted) { providers in
            PageDrop.page(from: providers, navigator: navigator) { id in navigator.openInSplit(.page(id)) }
        }
        .overlay {
            // An empty pane's picker has a drop area of its own; a page or PDF gets one over it while a page is over.
            if dropTargeted && navigator.split != nil {
                DropTargetArea("app:split.drop.here", isTargeted: true)
                    .padding(Spacing.s2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(Motion.easeOut(), value: dropTargeted)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("split-pane")
    }

    private var bar: some View {
        HStack(spacing: Spacing.s2) {
            if navigator.split != nil {
                // What the pane shows, as a chooser (⌃⌄, a pop-up button's mark): recent pages to switch to, or the
                // whole picker.
                Menu {
                    ForEach(model.tree.recent(limit: 8)) { page in
                        Button {
                            navigator.openInSplit(.page(page.id))
                        } label: {
                            Text(verbatim: "\(page.icon.map { $0 + "  " } ?? "")\(Self.title(page))")
                        }
                    }
                    Divider()
                    Button("app:split.more", action: navigator.showSplitPicker)
                        .accessibilityIdentifier("split-more")
                } label: {
                    HStack(spacing: Spacing.s2) {
                        current
                        IconView(.caretUpDown, size: TextSize.xs.rawValue).foregroundStyle(Theme.mutedForeground)
                    }
                    .padding(.horizontal, Spacing.s1_5)
                    .padding(.vertical, Spacing.s1)
                    .contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md))
                .menuIndicator(.hidden)
                .fixedSize()
                .help("app:split.change")
                .accessibilityIdentifier("split-change")
            } else {
                Text("app:split.pickTitle").font(.hk(.md, .medium)).foregroundStyle(Theme.subtleForeground)
            }
            Spacer(minLength: Spacing.s2)
            ToolbarIconButton("app:split.close", symbol: .x) { navigator.closeSplit() }
                .accessibilityIdentifier("split-close")
        }
        .padding(.horizontal, Spacing.s3)
        .frame(height: Size.pageBar)
    }

    @ViewBuilder private var current: some View {
        switch navigator.split {
        case .page(let id):
            PageIcon(model.tree.page(id)?.icon, size: 16)
            Text(Self.title(model.tree.page(id))).font(.hk(.md, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
        case .file(_, let label):
            IconView(.fileText, size: TextSize.sm.rawValue).foregroundStyle(Theme.subtleForeground)
            Text(label).font(.hk(.md, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch navigator.split {
        case .page:
            if let editor {
                EditorView(controller: editor)
            }
        case .file(let name, _):
            if let url = model.assets.file(named: name) {
                PDFViewer(url: url) {
                    #if os(macOS)
                        NSWorkspace.shared.open(url)
                    #endif
                }
            } else {
                notice("app:pdf.missing")
            }
        default:
            SplitPicker(navigator: navigator, dropTargeted: dropTargeted)
        }
    }

    private func notice(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.hk(.md)).foregroundStyle(Theme.mutedForeground).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func title(_ page: PageSummary?) -> String {
        guard let page, !page.title.isEmpty else { return String(localized: "app:page.untitled") }
        return page.title
    }
}

/// What an empty pane offers: the PDFs at hand (attached to the page on the left, open in tabs) and recent pages.
private struct SplitPicker: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    /// A page is being dragged over the pane: the drop area lights up.
    let dropTargeted: Bool
    @State private var attachedPDFs: [AssetReference] = []

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
                            navigator.openInSplit(.file(name: pdf.name, label: pdf.label))
                        }
                        .accessibilityIdentifier("split-pick-\(pdf.label)")
                    }
                }
                header("app:split.recent")
                if recent.isEmpty && pdfs.isEmpty {
                    Text("app:split.empty").font(.hk(.md)).foregroundStyle(Theme.mutedForeground).padding(Spacing.s2)
                }
                ForEach(recent) { page in
                    row(title: SplitPane.title(page), icon: AnyView(PageIcon(page.icon, size: 16))) {
                        navigator.openInSplit(.page(page.id))
                    }
                    .accessibilityIdentifier("split-pick-\(SplitPane.title(page))")
                }
            }
            .padding(Spacing.s3)
        }
        .task(id: navigator.route) {
            guard let id = navigator.route.pageID, let record = try? model.store.document(id: id) else {
                attachedPDFs = []
                return
            }
            attachedPDFs = record.assetReferences.filter { ($0.name as NSString).pathExtension.lowercased() == "pdf" }
        }
    }

    /// PDFs attached to the left page, then PDFs open in tabs — each once.
    private var pdfs: [(name: String, label: String)] {
        var seen = Set<String>()
        var out: [(name: String, label: String)] = []
        for reference in attachedPDFs where seen.insert(reference.name).inserted {
            out.append((reference.name, reference.label ?? reference.name))
        }
        for tab in navigator.tabs.tabs {
            if case .file(let name, let label) = tab.route, navigator.route != tab.route, seen.insert(name).inserted {
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
/// `editor/src/extensions/split-drop.ts`.) Mac and wide iPads only.
private struct EdgeDrop: ViewModifier {
    let navigator: Navigator
    @State private var showing = false
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var available: Bool {
        #if os(macOS)
            true
        #else
            sizeClass == .regular
        #endif
    }

    func body(content: Content) -> some View {
        if available {
            GeometryReader { proxy in
                content
                    .onDrop(of: PageDrop.types, delegate: Delegate(width: proxy.size.width, navigator: navigator, showing: $showing))
                    .overlay(alignment: .trailing) {
                        if showing {
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
            return DropProposal(operation: inside ? .copy : .cancel)
        }

        func dropExited(info: DropInfo) { showing = false }

        func performDrop(info: DropInfo) -> Bool {
            showing = false
            guard inZone(info) else { return false }
            return PageDrop.page(from: info.itemProviders(for: PageDrop.types), navigator: navigator) { id in
                navigator.openInSplit(.page(id))
            }
        }
    }
}
