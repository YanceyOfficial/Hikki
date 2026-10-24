import HikkiCore
import HikkiUI
import SwiftUI

/// Mac/iPad get a custom, Notion-like sidebar (full control over density and highlight); the iPhone's sidebar column
/// is its Home screen (`PhoneHome`), the page tree in its drawer (`PhoneDrawer`).
struct SidebarView: View {
    @Bindable var navigator: Navigator
    /// The window is wide (Mac / regular iPad): the page sidebar. iPhone (compact): Home.
    var wide = false

    var body: some View {
        #if os(iOS)
            if wide { PageSidebar(navigator: navigator) } else { PhoneHome(navigator: navigator) }
        #else
            PageSidebar(navigator: navigator)
        #endif
    }
}

// MARK: - Mac / iPad

#if DEBUG
    /// DEBUG hook HIKKI_DEBUG_SIDEBAR_STATS=<file>: how often the sidebar and its page rows evaluated their bodies,
    /// written to the file as JSON a few times a second (counts only) — the sidebar performance UI test reads it.
    enum SidebarRenderStats {
        private static let path = ProcessInfo.processInfo.environment["HIKKI_DEBUG_SIDEBAR_STATS"]
        private static var sidebar = 0
        private static var rows = 0
        private static var cells = 0
        private static var writer: Task<Void, Never>?

        static func sidebarRendered() { count { sidebar += 1 } }
        static func rowRendered() { count { rows += 1 } }
        static func cellRendered() { count { cells += 1 } }

        private static func count(_ bump: () -> Void) {
            guard let path else { return }
            bump()
            guard writer == nil else { return }
            writer = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    let json = #"{"sidebar":\#(sidebar),"rows":\#(rows),"cells":\#(cells)}"#
                    try? json.write(toFile: path, atomically: true, encoding: .utf8)
                }
            }
        }
    }
#endif

/// Drop handling for one sidebar row: tracks the pointer to show before / inside / after, and
/// moves the dragged page on drop (validity comes from `PageTree.destination`). Files dragged in from outside
/// (`SidebarFileDrop`) import as the page's children, the row tinted as for "inside".
private struct PageRowDropDelegate: DropDelegate {
    let target: String
    let navigator: Navigator
    let model: AppModel

    private func zone(_ info: DropInfo) -> DropZone? {
        guard let dragged = navigator.draggingPageID else { return nil }
        let zone = DropZone(y: info.location.y, height: Size.row)
        return model.tree.destination(dropping: dragged, onto: target, zone: zone) == nil ? nil : zone
    }

    func validateDrop(info: DropInfo) -> Bool { SidebarFileDrop.carriesFiles(info) || zone(info) != nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if SidebarFileDrop.carriesFiles(info) {
            navigator.dropIndicator = (target, .inside)
            return DropProposal(operation: .copy)
        }
        if let zone = zone(info) {
            navigator.dropIndicator = (target, zone)
            return DropProposal(operation: .move)
        }
        navigator.dropIndicator = nil
        return DropProposal(operation: .forbidden)
    }

    func dropExited(info: DropInfo) {
        if navigator.dropIndicator?.pageID == target { navigator.dropIndicator = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            navigator.dropIndicator = nil
            navigator.draggingPageID = nil
        }
        if SidebarFileDrop.carriesFiles(info) { return SidebarFileDrop.perform(info, parent: target, navigator: navigator) }
        guard let dragged = navigator.draggingPageID, let zone = zone(info) else { return false }
        let moved = model.movePage(dragged, onto: target, zone: zone)
        if moved, zone == .inside { navigator.expanded.insert(target) }
        return moved
    }
}

/// Drop onto the gap above the page tree: move the dragged page to the end of the top level (files dropped there
/// import at the top level).
private struct SectionDropDelegate: DropDelegate {
    let navigator: Navigator
    let model: AppModel
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool { navigator.draggingPageID != nil || SidebarFileDrop.carriesFiles(info) }
    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            isTargeted = false
            navigator.draggingPageID = nil
            navigator.dropIndicator = nil
        }
        if SidebarFileDrop.carriesFiles(info) { return SidebarFileDrop.perform(info, parent: nil, navigator: navigator) }
        guard let dragged = navigator.draggingPageID else { return false }
        return model.movePageToTopLevel(dragged)
    }
}

/// Top of the sidebar on Mac/iPad: workspace menu next to the traffic lights.
/// Bottom of the sidebar (Notion): the workspace's badge and name; its menu holds Settings and the other
/// workspace actions.
private struct WorkspaceSwitcher: View {
    let navigator: Navigator
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            // Settings only: import lives in Settings → Workspace (and File → Import…).
            Section {
                SettingsMenuItem(navigator: navigator)
            } header: {
                // The user's workspace name and where it lives.
                Text(verbatim: "\(model.workspace?.name ?? "Hikki") · \(location)")
            }
        } label: {
            // Compact, like Apple Music's account row: badge and name; the folder shows in the menu.
            SidebarFooterLabel(title: model.workspace?.name ?? "Hikki") {
                WorkspaceBadge(
                    initial: model.workspace?.initial ?? "H", icon: model.workspace?.icon, size: Size.iconButtonSm + Spacing.s0_5)
            }
        }
        .menuStyle(.button)
        .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.xl, hoverFill: Theme.sidebarAccent))
        .menuIndicator(.hidden)
        .accessibilityIdentifier("workspace-menu")
    }

    /// Where the workspace lives: the chosen folder, or "This device only".
    private var location: String { model.locationName }
}

// MARK: - The sidebar

/// Mac/iPad: a plain scrolling stack of our own rows. A native List painted its selection in the system accent and
/// swallowed row drops on iPad; selection, chevrons and icons are ours anyway, and the sidebar material comes from the
/// split view column.
private struct PageSidebar: View {
    @Environment(AppModel.self) private var model
    @Bindable var navigator: Navigator
    @State private var privateTargeted = false
    /// Files from outside are over the sidebar (not over a row): it is outlined in the colour tone.
    @State private var filesTargeted = false
    @Environment(\.colorTone) private var colorTone
    /// Read here once: the rows get the resolved pill colour as a value (a dynamic one picked up the sidebar's
    /// vibrancy), so no row reads the whole environment — that invalidated every row on any environment change.
    @Environment(\.self) private var environment

    var body: some View {
        #if DEBUG
            let _ = SidebarRenderStats.sidebarRendered()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.px) { sections }
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, Spacing.s1)
            }
            // A tab's Reveal in Sidebar: to the page's row (by its id in the tree), once its parents' expansion has
            // laid it out.
            .onChange(of: navigator.sidebarReveal) { _, request in
                guard let request else { return }
                Task {
                    withAnimation(Motion.easeOut()) { proxy.scrollTo(request.pageID, anchor: .center) }
                }
            }
        }
        .scrollIndicators(.never)
        .syncRefreshable()
        .overlay {
            if filesTargeted {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(colorTone.selectionFill.opacity(0.35))
                    .strokeBorder(colorTone.fill.opacity(0.7), lineWidth: 2)
                    .padding(Spacing.s2)
                    .allowsHitTesting(false)
            }
        }
        .animation(Motion.easeOut(), value: filesTargeted)
        .onDrop(of: SidebarFileDrop.types, delegate: SidebarFileDropDelegate(navigator: navigator, isTargeted: $filesTargeted))
        .modifier(NativeSidebarChrome(navigator: navigator))
        .navigationTitle(model.workspace?.name ?? "Hikki")  // l10n: allow (the user's workspace name)
        .toolbar {
            // Both trailing, side by side; with default placement the first item stretched and pushed the
            // menu into the overflow button.
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    navigator.newPage()
                } label: {
                    IconLabel("app:page.new", icon: .notePencil).labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("new-page")
            }
        }
    }

    @ViewBuilder private var sections: some View {
        Section {
            // Search is the glass field pinned above the list (NativeSidebarChrome). Notion's top row: the places as
            // icons side by side, the open one widening into a pill with its name.
            HStack(spacing: Spacing.s1) {
                SidebarPlace(route: .home, title: "app:nav.home", icon: .house, navigator: navigator)
                    .accessibilityIdentifier("nav-home")
                SidebarPlace(route: .trash, title: "app:nav.trash", icon: .trash, navigator: navigator, count: model.trash.count)
                    .accessibilityIdentifier("nav-trash")
                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.s1)
        }

        if !model.tree.favorites.isEmpty {
            Section {
                // Ids of their own: the tree below lists the same pages in this lazy stack, and a lazy stack with an
                // id twice drew the tree's row blank.
                ForEach(model.tree.favorites, id: \.favoriteRowID) { page in
                    // A shortcut: the selection shows on the page's own row in the tree, once (like a native list).
                    SidebarDestination(route: .page(page.id), navigator: navigator, selected: false, pill: pill) {
                        NativePageLabel(page: page)
                    }
                    .contextMenu { PageActionsFor(id: page.id, navigator: navigator) }
                }
            } header: {
                SidebarHeader("app:sidebar.favorites")
            }
        }

        Section {
            if model.tree.roots.isEmpty {
                Button {
                    navigator.newPage()
                } label: {
                    NativeSymbolLabel("app:sidebar.addPage", icon: .plus)
                }
                .buttonStyle(.plain)
            }
            // One flat list of plain rows (expanded subtrees inline), each redrawn only when what it shows changed:
            // the tree is rebuilt on every save, and the open page, a drag's drop line and expansion change often.
            let drop = navigator.dropIndicator
            let selectedID = navigator.route.pageID
            ForEach(model.tree.visibleRows(expanded: navigator.expanded)) { row in
                PageTreeRow(
                    row: row, selected: row.id == selectedID, drop: drop?.pageID == row.id ? drop?.zone : nil, pill: pill,
                    navigator: navigator
                )
                .equatable()
            }
        } header: {
            // No title (Notion's sidebar has none here either): a thin gap that still takes a dropped page to the
            // end of the top level.
            Color.clear
                .frame(height: Spacing.s3)
                .frame(maxWidth: .infinity)
                .background(privateTargeted ? colorTone.selectionFill : .clear, in: .rect(cornerRadius: Radius.md))
                .contentShape(.rect)
                .onDrop(
                    of: [.plainText] + SidebarFileDrop.types,
                    delegate: SectionDropDelegate(navigator: navigator, model: model, isTargeted: $privateTargeted))
        }
    }

    private var pill: Color.Resolved { Theme.sidebarAccent.resolve(in: environment) }
}

/// A page row of the tree: our own chevron inside the row, so it can turn white on the tone-filled selection (the
/// system disclosure triangle can't be recoloured). Everything it draws arrives as plain values, compared by
/// `.equatable()`: a save, a navigation or a drag redraws only the rows whose values changed. Nothing in its body reads
/// the navigator or the model (the menus read the page by id when they open).
private struct PageTreeRow: View, Equatable {
    let row: SidebarRow
    let selected: Bool
    let drop: DropZone?
    let pill: Color.Resolved
    let navigator: Navigator

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.selected == rhs.selected && lhs.drop == rhs.drop && lhs.pill == rhs.pill
            && lhs.navigator === rhs.navigator
    }

    var body: some View {
        #if DEBUG
            let _ = SidebarRenderStats.cellRendered()
        #endif
        SidebarDestination(route: .page(row.id), navigator: navigator, selected: selected, pill: pill, reservesChevron: false) {
            HoverPageRow(row: row, navigator: navigator)
                .padding(.leading, CGFloat(row.depth) * Spacing.s4)
        }
        .contextMenu { PageActionsFor(id: row.id, navigator: navigator) }
        .accessibilityIdentifier("page-row-\(row.title)")
        .modifier(PageRowDragDrop(row: row, indicator: drop, navigator: navigator))
    }
}

/// Page actions for a page named by id, read from the tree when the menu is built — so the row holding the menu doesn't
/// depend on the tree.
private struct PageActionsFor: View {
    @Environment(AppModel.self) private var model
    let id: String
    let navigator: Navigator

    var body: some View {
        if let page = model.tree.page(id) { PageActions(page: page, navigator: navigator) }
    }
}

/// A sidebar row that goes somewhere: a button with a grey selection pill — a List's own selection would be painted in
/// the system accent, not the colour tone.
private struct SidebarDestination<Label: View>: View {
    let route: Route
    let navigator: Navigator
    /// Whether the row is the open page (favorites never show it: the selection shows on the tree's row, once).
    let selected: Bool
    /// The resolved selection / hover fill (`PageSidebar.pill`).
    let pill: Color.Resolved
    /// Rows without a chevron of their own (Home, Trash, favorites) leave its slot empty, so icons line up
    /// with the tree's.
    var reservesChevron = true
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button {
            // Mac/iPad: the row's page joins the tab strip (or its tab gets focus).
            navigator.openFromSidebar(route)
        } label: {
            label
                .padding(.leading, reservesChevron ? Size.sidebarIcon + Spacing.s1 + Spacing.s2 : 0)
                // ~32pt rows, like Apple Music.
                .padding(.vertical, Spacing.s1_5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.s2)
                .contentShape(.rect)
                .environment(\.sidebarRowSelected, selected)
                .foregroundStyle(Theme.foreground)
        }
        .buttonStyle(.plain)
        // A grey selection pill, as in Apple Music (icons keep the colour tone), drawn flat behind the row:
        // as a list row background the sidebar rendered it raised, with a shadow.
        .background {
            // Resolved to a concrete colour: a dynamic one picked up the active sidebar's vibrancy.
            // Hover: the same grey, lighter.
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(selected ? Color(pill) : hovering ? Color(pill).opacity(0.55) : .clear)
        }
        .onHover { hovering = $0 }
        .animation(Motion.easeOut(Motion.popOut), value: hovering)
        // The padding moved inside the button for the pill; pull it back so content keeps its place.
        .padding(.horizontal, -Spacing.s2)
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Drag a page row onto another to nest it, or onto its top/bottom edge to move it before/after (Mac/iPad).
/// Same rules as the custom sidebar (PageRowDropDelegate / PageTree.destination); the indicator is a line for
/// before/after and a tint for "inside".
private struct PageRowDragDrop: ViewModifier {
    let row: SidebarRow
    /// Where a page held over this row would land (nil: nothing is held over it).
    let indicator: DropZone?
    let navigator: Navigator
    @Environment(AppModel.self) private var model
    @Environment(\.colorTone) private var colorTone

    func body(content: Content) -> some View {
        let depth = row.depth
        content
            .background {
                if indicator == .inside {
                    RoundedRectangle(cornerRadius: Radius.lg).fill(colorTone.selectionFill)
                }
            }
            .overlay(alignment: indicator == .before ? .top : .bottom) {
                if indicator == .before || indicator == .after {
                    colorTone.fill.frame(height: Spacing.s0_5).clipShape(.capsule)
                        .padding(.leading, CGFloat(depth) * Spacing.s3_5 + Spacing.s3_5)
                }
            }
            .onDrag {
                navigator.draggingPageID = row.id
                // The payload is the page's link: the editor makes a labelled hyperlink of it and the tab strip
                // opens it. The sidebar's own drops go by `draggingPageID`.
                return PageLink.dragItem(row.id)
            } preview: {
                // The row as a rounded chip (the default preview was the bare row, square-cornered).
                HStack(spacing: Spacing.s2) {
                    PageIcon(row.icon, size: Size.pageIcon)
                    Text(PageTitle.display(row.title))
                        .font(.hk(.md))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                }
                .padding(.horizontal, Spacing.s2_5)
                .padding(.vertical, Spacing.s1_5)
                .background(Theme.popover, in: .rect(cornerRadius: Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.border, lineWidth: 1))
                .clipShape(.rect(cornerRadius: Radius.lg))
            }
            .onDrop(
                of: [.plainText] + SidebarFileDrop.types,
                delegate: PageRowDropDelegate(target: row.id, navigator: navigator, model: model)
            )
            // Outline level for VoiceOver (and UI tests): "level 1" at the top, +1 per nesting.
            .accessibilityValue("level \(depth + 1)")
    }
}

/// A section title in the Mac/iPad sidebar stack (Favorites, Private), styled like the system sidebar's.
private struct SidebarHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.hk(.sm, .semibold))
            .foregroundStyle(Theme.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s2)
            .padding(.top, Spacing.s4)
            .padding(.bottom, Spacing.s1)
    }
}

/// The expand/collapse chevron of a native sidebar row (Mac/iPad). Every page row reserves its slot so icons
/// line up, as with the system triangle; it takes the row's colour (white on the selection).
private struct DisclosureChevron: View {
    /// nil: the page has no subpages (the slot stays blank).
    let isExpanded: Bool?
    let toggle: () -> Void

    var body: some View {
        Group {
            if let isExpanded {
                Button {
                    withAnimation(Motion.easeOut()) { toggle() }
                } label: {
                    IconView(.caretRight, size: TextSize.xs.rawValue)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: Size.sidebarIcon + Spacing.s1, height: Size.iconButtonSm)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "app:sidebar.collapse" : "app:sidebar.expand")
            } else {
                Color.clear.frame(width: Size.sidebarIcon + Spacing.s1, height: Size.iconButtonSm)
            }
        }
    }
}

/// A system sidebar row for a fixed destination: Phosphor icon (tinted like system sidebar icons) + title.
private struct NativeSymbolLabel: View {
    let title: LocalizedStringKey
    let icon: Icon
    @Environment(\.colorTone) private var colorTone
    @Environment(\.sidebarRowSelected) private var selected

    init(_ title: LocalizedStringKey, icon: Icon) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            // One fixed, centred slot so symbols of different widths (house vs. magnifying glass) line up.
            icon.glyph.imageScale(.large).frame(width: Size.sidebarIcon + Spacing.s1)
                // Explicit, so neither the system accent nor list tinting replaces the colour tone; on the
                // selection it takes the row's on-fill colour.
                .foregroundStyle(colorTone.fill)
        }
    }
}

/// A system sidebar row for a page: its emoji (or the page glyph) + title, system font.
private struct NativePageLabel: View {
    let page: PageSummary
    @Environment(\.sidebarRowSelected) private var selected
    @Environment(\.colorTone) private var colorTone

    var body: some View {
        Label {
            if page.title.isEmpty {
                Text("app:page.untitled").foregroundStyle(Theme.mutedForeground)
            } else {
                Text(verbatim: page.title)  // the page's own title
            }
        } icon: {
            PageIcon(page.icon, size: TextSize.base.rawValue)
                .frame(width: Size.sidebarIcon + Spacing.s1)
        }
    }
}

/// A page row's content in the Mac/iPad tree: expand chevron, icon and title; on hover "+" (new subpage) and ⋯
/// (page actions) appear at the end (Notion).
private struct HoverPageRow: View {
    let row: SidebarRow
    let navigator: Navigator
    @State private var hovering = false

    var body: some View {
        #if DEBUG
            let _ = SidebarRenderStats.rowRendered()
        #endif
        HStack(spacing: Spacing.s2) {
            // The chevron keeps its own slot (blank for pages without subpages), always visible: swapping it
            // in for the icon on hover hid where a page could expand.
            DisclosureChevron(isExpanded: row.hasChildren ? row.isExpanded : nil) { [navigator, id = row.id] in
                if navigator.expanded.contains(id) { navigator.expanded.remove(id) } else { navigator.expanded.insert(id) }
            }
            PageIcon(row.icon, size: TextSize.base.rawValue)
                .frame(width: Size.sidebarIcon + Spacing.s1, height: Size.iconButtonSm)
            Group {
                if row.title.isEmpty {
                    Text("app:page.untitled").foregroundStyle(Theme.mutedForeground)
                } else {
                    Text(verbatim: row.title)  // the page's own title
                }
            }
            .lineLimit(1)
            Spacer(minLength: Spacing.s1)
            if hovering {
                HStack(spacing: Spacing.px) {
                    Menu {
                        PageActionsFor(id: row.id, navigator: navigator)
                    } label: {
                        IconView(.dotsThree, size: TextSize.sm.rawValue)
                            .frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
                            .contentShape(.rect)
                    }
                    .menuStyle(.button)
                    .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md, hoverFill: Theme.sidebarAccent))
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("app:common.more")
                    Button {
                        navigator.newPage(parentId: row.id)
                    } label: {
                        IconView(.plus, size: TextSize.sm.rawValue)
                            .frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
                            .contentShape(.rect)
                    }
                    .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md, hoverFill: Theme.sidebarAccent))
                    .help("app:page.addInside")
                    .accessibilityLabel("app:page.addInside")
                }
                .foregroundStyle(Theme.mutedForeground)
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Shared

/// "Move to Trash" asks first, the same way wherever it is chosen (Notion's): the page's title, how many subpages go
/// along, a destructive Move to Trash and Cancel. `pageID` set shows it; ContentView presents the one for page menus
/// (`Navigator.trashRequestID`), a sheet with its own Move to Trash (the iPhone's ⋯) presents its own over itself and
/// closes with `onTrash`.
struct TrashConfirmation: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var pageID: String?
    var onTrash: () -> Void = {}

    func body(content: Content) -> some View {
        let page = pageID.flatMap { model.tree.page($0) }
        let subpages = page.map { model.tree.subpageCount(of: $0.id) } ?? 0
        let title = page?.displayTitle ?? ""
        content.alert(
            "app:page.confirmTrash \(title)",
            isPresented: Binding(get: { page != nil }, set: { if !$0 { pageID = nil } })
        ) {
            Button("app:page.moveToTrash", role: .destructive) {
                guard let page else { return }
                onTrash()
                model.moveToTrash(id: page.id)
            }
            .accessibilityIdentifier("confirm-trash")
            Button("app:common.cancel", role: .cancel) {}
        } message: {
            switch subpages {
            case 0: Text("app:page.confirmTrash.hint")
            case 1: Text("app:page.confirmTrash.subpage")
            default: Text("app:page.confirmTrash.subpages \(subpages.formatted())")
            }
        }
    }
}

/// Shared page actions for the ⋯ menu, context menus and the page bar.
struct PageActions: View {
    @Environment(AppModel.self) private var model
    /// Split view needs a wide window (Mac, a regular-width iPad) — the window's width class, set by ContentView: the
    /// sidebar column's own is compact on iPad, which hid "Open in Split View" there.
    @Environment(\.splitAvailable) private var splitAvailable
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif
    let page: PageSummary
    let navigator: Navigator

    var body: some View {
        // Notion's page menu: a titled section, grouped actions, and when it was last edited at the bottom.
        Section("app:page.menuTitle") {
            Button {
                model.setFavorite(!page.isFavorite, id: page.id)
            } label: {
                IconLabel(page.isFavorite ? "app:page.unfavorite" : "app:page.favorite", icon: page.isFavorite ? .starFill : .star)
            }
            // Locked: read-only everywhere until unlocked (⇧⌘L in the Page menu binds the key).
            Button {
                model.setLocked(!page.isLocked, id: page.id)
            } label: {
                IconLabel(page.isLocked ? "app:page.unlock" : "app:page.lock", icon: page.isLocked ? .lockSimpleOpen : .lockSimple)
            }
            .accessibilityIdentifier("lock-toggle")
        }
        Section {
            Button {
                copyLink()
            } label: {
                IconLabel("app:page.copyLink", icon: .link)
            }
            Button {
                model.duplicate(id: page.id)
            } label: {
                IconLabel("app:page.duplicate", icon: .copy)
            }
            Button {
                navigator.rename(page.id)
            } label: {
                IconLabel("app:page.rename", icon: .pencilSimple)
            }
            moveToMenu
            Button {
                navigator.newPage(parentId: page.id)
            } label: {
                IconLabel("app:page.addInside", icon: .plus)
            }
            // Markdown / HTML / text files (or folders of them) as subpages of this page.
            Button {
                navigator.importFiles(into: page.id)
            } label: {
                IconLabel("app:page.importInside", icon: .trayArrowDown)
            }
            .accessibilityIdentifier("page-import")
            // Asks first (ContentView presents `TrashConfirmation`): a menu item one row from Import is easy to hit.
            Button(role: .destructive) {
                navigator.trashRequestID = page.id
            } label: {
                IconLabel("app:page.moveToTrash", icon: .trash)
            }
        }
        Section {
            if Navigator.usesTabs {
                Button {
                    navigator.openInNewTab(.page(page.id))
                } label: {
                    IconLabel("app:page.openInNewTab", icon: .browsers)
                }
            }
            if splitAvailable {
                Button {
                    navigator.openInSplit(.page(page.id))
                } label: {
                    IconLabel("app:split.openPage", icon: .squareSplitHorizontal)
                }
                .accessibilityIdentifier("open-in-split")
            }
            #if os(macOS)
                Button {
                    openWindow(id: "page", value: page.id)
                } label: {
                    IconLabel("app:page.openInNewWindow", icon: .appWindow)
                }
            #endif
        }
        Section {
            Text("app:page.lastEdited \(page.updatedAt, format: .dateTime.month().day().hour().minute())")
        }
    }

    /// Notion's "Move page to…": the window presents the picker (`MovePageSheet`).
    private var moveToMenu: some View {
        Button {
            navigator.movePageID = page.id
        } label: {
            IconLabel("app:page.moveTo", icon: .arrowBendUpRight)
        }
        .accessibilityIdentifier("page-move")
    }

    private func copyLink() {
        PageLink.copyToPasteboard(page.id)
    }
}

extension PageLink {
    /// Puts the page's hikki:// link on the pasteboard (Copy link, in menus and on ⌥⌘C).
    static func copyToPasteboard(_ id: String) {
        let url = PageLink.url(for: id)
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #else
            UIPasteboard.general.url = url
        #endif
    }
}

/// "Settings…" in the workspace menus: the Settings dialog over the window.
private struct SettingsMenuItem: View {
    let navigator: Navigator

    var body: some View {
        Button {
            navigator.isShowingSettings = true
        } label: {
            IconLabel("app:settings.open", icon: .gearSix)
        }
        .accessibilityIdentifier("settings-open")
    }
}

/// The sidebar's chrome: the glass search field pinned on top, the workspace switcher at the bottom.
private struct NativeSidebarChrome: ViewModifier {
    let navigator: Navigator
    @Environment(\.fullScreenSlack) private var fullScreenSlack

    func body(content: Content) -> some View {
        content
            // Bars (not plain insets): rows scrolling under them fade out (the scroll edge effect) instead
            // of running into their content.
            .safeAreaBar(edge: .top) {
                GlassSearchField("app:nav.search", shortcut: "⌘K") { navigator.isSearching = true }
                    .accessibilityIdentifier("sidebar-search")
                    .padding(.horizontal, Spacing.s3)
                    .padding(.bottom, Spacing.s1)
                    // Full screen: room for the toolbar row to slide down with the menu bar (FullScreenChrome.swift),
                    // plus a breath so the field never touches the row once it has come down.
                    .padding(.top, fullScreenSlack > 0 ? fullScreenSlack + Spacing.s3 : 0)
            }
            .safeAreaBar(edge: .bottom) {
                WorkspaceSwitcher(navigator: navigator)
                    .padding(.horizontal, Spacing.s2)
                    .padding(.top, Spacing.s1_5)
                    .padding(.bottom, Spacing.s2)
            }
    }

}

extension EnvironmentValues {
    /// Set on a selected native sidebar row (Mac/iPad), so its label draws on the tone's fill.
    @Entry var sidebarRowSelected = false
    /// The window is wide enough for split view (ContentView's `wide`).
    @Entry var splitAvailable = false
}

/// One place in the sidebar's top row (Mac/iPad): an icon button; the open one is a grey pill with its name (Notion).
private struct SidebarPlace: View {
    let route: Route
    let title: LocalizedStringKey
    let icon: Icon
    let navigator: Navigator
    var count = 0
    @Environment(\.colorTone) private var colorTone
    @Environment(\.self) private var environment
    @State private var hovering = false

    var body: some View {
        let selected = navigator.route == route
        Button {
            navigator.openFromSidebar(route)
        } label: {
            HStack(spacing: Spacing.s1_5) {
                icon.glyph
                    .imageScale(.large)
                    .foregroundStyle(selected ? colorTone.fill : Theme.subtleForeground)
                if selected {
                    Text(title).font(.hk(.md, .medium)).foregroundStyle(Theme.foreground)
                    if count > 0 {
                        Text(count, format: .number).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
            .padding(.horizontal, Spacing.s2_5)
            .frame(height: Size.iconButton + Spacing.s2)
            .background {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(
                        selected
                            ? Color(Theme.sidebarAccent.resolve(in: environment))
                            : hovering ? Color(Theme.sidebarAccent.resolve(in: environment)).opacity(0.55) : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.easeOut(), value: selected)
        .animation(Motion.easeOut(Motion.popOut), value: hovering)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

extension PageSummary {
    /// A favorite's row id in the sidebar, apart from the page's own row in the tree.
    fileprivate var favoriteRowID: String { "favorite:" + id }
}
