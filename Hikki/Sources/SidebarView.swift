import HikkiCore
import HikkiUI
import SwiftUI

/// Mac/iPad get a custom, Notion-like sidebar (full control over density and highlight);
/// iPhone keeps a List so rows push the page with native navigation.
struct SidebarView: View {
    @Bindable var navigator: Navigator
    /// The window is wide (Mac / regular iPad): our own rows in a stack, the workspace switcher at the bottom.
    /// iPhone: a native List that pushes pages.
    var wide = false

    var body: some View {
        PhoneSidebar(navigator: navigator, wideSidebar: wide)
    }
}

// MARK: - Mac / iPad

/// Drop handling for one sidebar row: tracks the pointer to show before / inside / after, and
/// moves the dragged page on drop (validity comes from `PageTree.destination`).
private struct PageRowDropDelegate: DropDelegate {
    let target: String
    let navigator: Navigator
    let model: AppModel

    private func zone(_ info: DropInfo) -> DropZone? {
        guard let dragged = navigator.draggingPageID else { return nil }
        let zone = DropZone(y: info.location.y, height: Size.row)
        return model.tree.destination(dropping: dragged, onto: target, zone: zone) == nil ? nil : zone
    }

    func validateDrop(info: DropInfo) -> Bool { zone(info) != nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
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
        guard let dragged = navigator.draggingPageID, let zone = zone(info) else { return false }
        let moved = model.movePage(dragged, onto: target, zone: zone)
        if moved, zone == .inside { navigator.expanded.insert(target) }
        return moved
    }
}

/// Drop onto the "app:sidebar.private" header: move the dragged page to the end of the top level.
private struct SectionDropDelegate: DropDelegate {
    let navigator: Navigator
    let model: AppModel
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool { navigator.draggingPageID != nil }
    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            isTargeted = false
            navigator.draggingPageID = nil
            navigator.dropIndicator = nil
        }
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
    @State private var renaming = false

    var body: some View {
        Menu {
            Section {
                SettingsMenuItem(navigator: navigator)
                Button("app:workspace.rename") { renaming = true }
                    .accessibilityIdentifier("workspace-rename")
                ShareLink("app:workspace.exportLogs", items: model.exportableFiles)
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
        .renameWorkspaceAlert(isPresented: $renaming)
    }

    /// Where the workspace lives: the chosen folder, or "This device only".
    private var location: String {
        if case .folder(_, let displayName) = model.workspace?.location { return displayName }
        return String(localized: "app:onboarding.location.device")
    }
}

// MARK: - iPhone

private struct PhoneSidebar: View {
    @Environment(AppModel.self) private var model
    @Bindable var navigator: Navigator
    let wideSidebar: Bool
    @State private var renaming = false
    @State private var privateTargeted = false
    @Environment(\.colorTone) private var colorTone

    var body: some View {
        Group {
            if wideSidebar {
                // Mac/iPad: a plain scrolling stack of our own rows. A native List painted its selection in the
                // system accent and swallowed row drops on iPad; selection, chevrons and icons are ours anyway,
                // and the sidebar material comes from the split view column.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.px) { sections }
                        .padding(.horizontal, Spacing.s4)
                        .padding(.vertical, Spacing.s1)
                }
                .scrollIndicators(.never)
            } else {
                List(selection: $navigator.sidebarSelection) { sections }
                    .listStyle(.sidebar)
            }
        }
        .modifier(NativeSidebarChrome(navigator: navigator, isWide: wideSidebar))
        .navigationTitle(model.workspace?.name ?? "Hikki")  // l10n: allow (the user's workspace name)
        .renameWorkspaceAlert(isPresented: $renaming)
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
                // The workspace menu (iPhone has no sidebar header; Mac/iPad have the footer switcher).
                if !wideSidebar {
                    Menu {
                        SettingsMenuItem(navigator: navigator)
                        Button("app:workspace.rename") { renaming = true }
                            .accessibilityIdentifier("workspace-rename")
                        ShareLink("app:workspace.exportLogs", items: model.exportableFiles)
                    } label: {
                        IconLabel("app:common.more", icon: .dotsThreeCircle).labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("workspace-more")
                }
            }
        }
    }

    @ViewBuilder private var sections: some View {
        Section {
            // Mac/iPad: search is the glass field pinned above the list (NativeSidebarChrome).
            if !wideSidebar {
                Button {
                    navigator.isSearching = true
                } label: {
                    NativeSymbolLabel("app:nav.search", icon: .magnifyingGlass)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar-search")
            }
            SidebarDestination(route: .home, navigator: navigator, wide: wideSidebar) {
                NativeSymbolLabel("app:nav.home", icon: .house)
            }
            .accessibilityIdentifier("nav-home")
            // Trash sits with Home (as in the first design), not at the end of the tree.
            SidebarDestination(route: .trash, navigator: navigator, wide: wideSidebar) {
                HStack {
                    NativeSymbolLabel("app:nav.trash", icon: .trash)
                    // List's .badge doesn't exist in the stack; the same count, drawn here.
                    if wideSidebar, !model.trash.isEmpty {
                        Spacer()
                        Text(model.trash.count, format: .number).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .badge(wideSidebar ? 0 : model.trash.count)
        }

        if !model.tree.favorites.isEmpty {
            Section {
                ForEach(model.tree.favorites) { page in
                    // A shortcut: the selection shows on the page's own row in the tree, once (like a native list).
                    SidebarDestination(route: .page(page.id), navigator: navigator, wide: wideSidebar, showsSelection: false) {
                        NativePageLabel(page: page)
                    }
                    .contextMenu { PageActions(page: page, navigator: navigator) }
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
            PhoneTree(nodes: model.tree.roots, depth: 0, navigator: navigator, wide: wideSidebar)
        } header: {
            // No "+" here: New page sits in the toolbar on every platform. Dropping a page here moves it
            // to the end of the top level.
            SidebarHeader("app:sidebar.private")
                .background(privateTargeted ? colorTone.selectionFill : .clear, in: .rect(cornerRadius: Radius.md))
                .onDrop(
                    of: [.plainText], delegate: SectionDropDelegate(navigator: navigator, model: model, isTargeted: $privateTargeted))
        }
    }

}

private struct PhoneTree: View {
    let nodes: [PageNode]
    let depth: Int
    @Bindable var navigator: Navigator
    var wide = false

    var body: some View {
        ForEach(nodes) { node in
            if wide {
                // Mac/iPad: our own chevron inside the row, so it can turn white on the tone-filled selection
                // (the system disclosure triangle can't be recoloured); children follow as their own rows.
                row(node, chevron: node.children.isEmpty ? nil : expansion(node.id))
                if !node.children.isEmpty, navigator.expanded.contains(node.id) {
                    PhoneTree(nodes: node.children, depth: depth + 1, navigator: navigator, wide: wide)
                }
            } else if node.children.isEmpty {
                row(node, chevron: nil)
            } else {
                // iPhone: the system disclosure triangle for subpages.
                DisclosureGroup(isExpanded: expansion(node.id)) {
                    PhoneTree(nodes: node.children, depth: depth + 1, navigator: navigator, wide: wide)
                } label: {
                    row(node, chevron: nil)
                }
            }
        }
    }

    @ViewBuilder private func row(_ node: PageNode, chevron: Binding<Bool>?) -> some View {
        if wide {
            destination(node, chevron: chevron).modifier(PageRowDragDrop(page: node.page, depth: depth, navigator: navigator))
        } else {
            destination(node, chevron: chevron)
        }
    }

    private func destination(_ node: PageNode, chevron: Binding<Bool>?) -> some View {
        SidebarDestination(route: .page(node.id), navigator: navigator, wide: wide, reservesChevron: false) {
            if wide {
                HoverPageRow(page: node.page, isExpanded: chevron, navigator: navigator)
                    .padding(.leading, CGFloat(depth) * Spacing.s4)
            } else {
                NativePageLabel(page: node.page)
            }
        }
        .contextMenu { PageActions(page: node.page, navigator: navigator) }
        .accessibilityIdentifier("page-row-\(node.page.title)")
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(
            get: { navigator.expanded.contains(id) },
            set: { open in if open { navigator.expanded.insert(id) } else { navigator.expanded.remove(id) } }
        )
    }
}

/// A sidebar row that goes somewhere. iPhone: a NavigationLink (pushes). Mac/iPad: a button with a grey
/// selection pill — the List's own selection would be painted in the system accent, not the colour tone.
private struct SidebarDestination<Label: View>: View {
    let route: Route
    let navigator: Navigator
    let wide: Bool
    var showsSelection = true
    /// Rows without a chevron of their own (Home, Trash, favorites) leave its slot empty, so icons line up
    /// with the tree's.
    var reservesChevron = true
    @ViewBuilder let label: Label
    @Environment(\.colorTone) private var colorTone
    @Environment(\.self) private var environment
    @State private var hovering = false

    var body: some View {
        if wide {
            let selected = showsSelection && navigator.route == route
            Button {
                if let id = route.pageID { navigator.open(id) } else { navigator.go(route) }
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
                    .fill(
                        selected
                            ? Color(Theme.sidebarAccent.resolve(in: environment))
                            : hovering ? Color(Theme.sidebarAccent.resolve(in: environment)).opacity(0.55) : .clear)
            }
            .onHover { hovering = $0 }
            .animation(Motion.easeOut(Motion.popOut), value: hovering)
            // The padding moved inside the button for the pill; pull it back so content keeps its place.
            .padding(.horizontal, -Spacing.s2)
            .listRowBackground(Color.clear)
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            NavigationLink(value: route) { label }
        }
    }
}

/// Drag a page row onto another to nest it, or onto its top/bottom edge to move it before/after (Mac/iPad).
/// Same rules as the custom sidebar (PageRowDropDelegate / PageTree.destination); the indicator is a line for
/// before/after and a tint for "inside".
private struct PageRowDragDrop: ViewModifier {
    let page: PageSummary
    let depth: Int
    let navigator: Navigator
    @Environment(AppModel.self) private var model
    @Environment(\.colorTone) private var colorTone

    func body(content: Content) -> some View {
        let indicator = navigator.dropIndicator?.pageID == page.id ? navigator.dropIndicator?.zone : nil
        content
            .background {
                if indicator == .inside {
                    RoundedRectangle(cornerRadius: Radius.lg).fill(colorTone.selectionFill)
                }
            }
            .overlay(alignment: indicator == .before ? .top : .bottom) {
                if indicator == .before || indicator == .after {
                    colorTone.fill.frame(height: 2).clipShape(.capsule)
                        .padding(.leading, CGFloat(depth) * Spacing.s3_5 + Spacing.s3_5)
                }
            }
            .onDrag {
                navigator.draggingPageID = page.id
                return NSItemProvider(object: page.id as NSString)
            }
            .onDrop(of: [.plainText], delegate: PageRowDropDelegate(target: page.id, navigator: navigator, model: model))
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
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s2)
            .padding(.top, Spacing.s4)
            .padding(.bottom, Spacing.s1)
    }
}

/// The expand/collapse chevron of a native sidebar row (Mac/iPad). Every page row reserves its slot so icons
/// line up, as with the system triangle; it takes the row's colour (white on the selection).
private struct DisclosureChevron: View {
    let isExpanded: Binding<Bool>?
    @Environment(\.sidebarRowSelected) private var selected
    @Environment(\.colorTone) private var colorTone

    var body: some View {
        Group {
            if let isExpanded {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { isExpanded.wrappedValue.toggle() }
                } label: {
                    IconView(.caretRight, size: TextSize.xs.rawValue)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: Size.sidebarIcon + Spacing.s1, height: Size.iconButtonSm)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded.wrappedValue ? "app:sidebar.collapse" : "app:sidebar.expand")
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
                Text("app:page.untitled").foregroundStyle(.secondary)
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
    let page: PageSummary
    let isExpanded: Binding<Bool>?
    let navigator: Navigator
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.s2) {
            // The chevron keeps its own slot (blank for pages without subpages), always visible: swapping it
            // in for the icon on hover hid where a page could expand.
            DisclosureChevron(isExpanded: isExpanded)
            PageIcon(page.icon, size: TextSize.base.rawValue)
                .frame(width: Size.sidebarIcon + Spacing.s1, height: Size.iconButtonSm)
            Group {
                if page.title.isEmpty {
                    Text("app:page.untitled").foregroundStyle(.secondary)
                } else {
                    Text(verbatim: page.title)  // the page's own title
                }
            }
            .lineLimit(1)
            Spacer(minLength: Spacing.s1)
            if hovering {
                HStack(spacing: Spacing.px) {
                    Menu {
                        PageActions(page: page, navigator: navigator)
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
                        navigator.newPage(parentId: page.id)
                    } label: {
                        IconView(.plus, size: TextSize.sm.rawValue)
                            .frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
                            .contentShape(.rect)
                    }
                    .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md, hoverFill: Theme.sidebarAccent))
                    .help("app:page.addInside")
                    .accessibilityLabel("app:page.addInside")
                }
                .foregroundStyle(.secondary)
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Shared

/// ⋯ button on a sidebar row.
struct PageRowMenu: View {
    let page: PageSummary
    let navigator: Navigator

    var body: some View {
        Menu {
            PageActions(page: page, navigator: navigator)
        } label: {
            IconView(.dotsThree, size: TextSize.xs.rawValue)
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(HoverHighlightStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("app:sidebar.rowMenuHelp")
    }
}

/// Shared page actions for the ⋯ menu, context menus and the page bar.
struct PageActions: View {
    @Environment(AppModel.self) private var model
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
            Button(role: .destructive) {
                model.moveToTrash(id: page.id)
            } label: {
                IconLabel("app:page.moveToTrash", icon: .trash)
            }
        }
        Section {
            Button {
                navigator.openInNewTab(.page(page.id))
            } label: {
                IconLabel("app:page.openInNewTab", icon: .browsers)
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

    /// Every other page (not this one's subtree), indented by depth, plus the top level.
    private var moveToMenu: some View {
        Menu {
            if page.parentId != nil {
                Button("app:page.moveToTopLevel") { model.movePageToTopLevel(page.id) }
            }
            ForEach(model.tree.moveTargets(for: page.id), id: \.page.id) { target in
                Button {
                    model.movePage(page.id, onto: target.page.id, zone: .inside)
                } label: {
                    // The page's own title, shown as-is (indented by depth like the sidebar).
                    Text(verbatim: String(repeating: "    ", count: target.depth) + displayTitle(target.page))
                }
            }
        } label: {
            IconLabel("app:page.moveTo", icon: .arrowBendUpRight)
        }
    }

    private func displayTitle(_ page: PageSummary) -> String {
        let icon = page.icon.map { "\($0) " } ?? ""
        return icon + (page.title.isEmpty ? String(localized: "app:page.untitled") : page.title)
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

// MARK: - Rename workspace

private struct RenameWorkspaceAlert: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .alert("app:workspace.renameTitle", isPresented: $isPresented) {
                TextField("app:onboarding.name.placeholder", text: $draft)
                Button("app:common.cancel", role: .cancel) {}
                Button("app:common.save") { model.renameWorkspace(draft) }
                    .disabled(Workspace.normalizedName(draft) == nil)
                    .accessibilityIdentifier("workspace-rename-save")
            }
            .onChange(of: isPresented) { _, presented in
                if presented { draft = model.workspace?.name ?? "" }
            }
    }
}

extension View {
    fileprivate func renameWorkspaceAlert(isPresented: Binding<Bool>) -> some View {
        modifier(RenameWorkspaceAlert(isPresented: isPresented))
    }
}

/// "Settings…" in the workspace menus: the Settings window on macOS, the settings sheet on iOS.
private struct SettingsMenuItem: View {
    let navigator: Navigator
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        Button {
            #if os(macOS)
                openSettings()
            #else
                navigator.isShowingSettings = true
            #endif
        } label: {
            IconLabel("app:settings.open", icon: .gearSix)
        }
        .accessibilityIdentifier("settings-open")
    }
}

/// EXPERIMENT: Mac/iPad sidebar chrome for the native look.
private struct NativeSidebarChrome: ViewModifier {
    let navigator: Navigator
    let isWide: Bool

    func body(content: Content) -> some View {
        if isWide {
            content
                // Bars (not plain insets): rows scrolling under them fade out (the scroll edge effect) instead
                // of running into their content.
                .safeAreaBar(edge: .top) {
                    GlassSearchField("app:nav.search", shortcut: "⌘K") { navigator.isSearching = true }
                        .accessibilityIdentifier("sidebar-search")
                        .padding(.horizontal, Spacing.s3)
                        .padding(.bottom, Spacing.s1)
                }
                // Full screen: the auto-hidden toolbar slides down over the rows (Photos fades them under it).
                .fullScreenScrim(Theme.sidebar)
                .safeAreaBar(edge: .bottom) {
                    WorkspaceSwitcher(navigator: navigator)
                        .padding(.horizontal, Spacing.s2)
                        .padding(.top, Spacing.s1_5)
                        .padding(.bottom, Spacing.s2)
                }
        } else {
            content.scrollContentBackground(.hidden).background(Theme.sidebar)
        }
    }

}

extension EnvironmentValues {
    /// Set on a selected native sidebar row (Mac/iPad), so its label draws on the tone's fill.
    @Entry var sidebarRowSelected = false
}
