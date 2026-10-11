import HikkiCore
import HikkiUI
import SwiftUI

/// Mac/iPad get a custom, Notion-like sidebar (full control over density and highlight);
/// iPhone keeps a List so rows push the page with native navigation.
struct SidebarView: View {
    @Bindable var navigator: Navigator
    let customChrome: Bool
    /// The window is wide (Mac / regular iPad): native sidebar footer instead of the nav-bar menu.
    var wide = false

    var body: some View {
        if customChrome {
            DesktopSidebar(navigator: navigator)
        } else {
            PhoneSidebar(navigator: navigator, wideSidebar: wide)
        }
    }
}

// MARK: - Mac / iPad

private struct DesktopSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorTone) private var colorTone
    @Bindable var navigator: Navigator
    @State private var privateTargeted = false

    var body: some View {
        VStack(spacing: Spacing.s0) {
            SidebarSearchField("app:nav.search", shortcut: "⌘K") { navigator.isSearching = true }
                .accessibilityIdentifier("sidebar-search")
                .padding(.horizontal, Spacing.s3)
                .padding(.top, Spacing.s3)
            SidebarNavBar([
                .init(id: "home", title: String(localized: "app:nav.home"), symbol: .house, isSelected: navigator.route == .home) {
                    navigator.go(.home)
                },
                .init(id: "trash", title: String(localized: "app:nav.trash"), symbol: .trash, isSelected: navigator.route == .trash) {
                    navigator.go(.trash)
                },
            ]) {
                EmptyView()
            }
            .padding(.horizontal, Spacing.s2)
            .padding(.top, Spacing.s2)
            .padding(.bottom, Spacing.s1)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.px) {
                    if !model.tree.favorites.isEmpty {
                        SectionTitle("app:sidebar.favorites")
                        ForEach(model.tree.favorites) { page in
                            pageRow(page, depth: 0, children: [])
                        }
                    }

                    SectionTitle("app:sidebar.private") {
                        SidebarIconButton("app:page.new", symbol: .plus) { navigator.newPage() }
                            .accessibilityIdentifier("new-page-section")
                    }
                    .background(privateTargeted ? colorTone.selectionFill : .clear, in: .rect(cornerRadius: Radius.md))
                    .onDrop(
                        of: [.plainText], delegate: SectionDropDelegate(navigator: navigator, model: model, isTargeted: $privateTargeted))
                    if model.tree.roots.isEmpty {
                        item(Route?.none, "app:sidebar.addPage", symbol: .plus) { navigator.newPage() }
                    }
                    DesktopTree(nodes: model.tree.roots, depth: 0, navigator: navigator)
                }
                .padding(.vertical, Spacing.s1_5)
            }
            .scrollIndicators(.never)

            WorkspaceSwitcher(navigator: navigator)
                .padding(.horizontal, Spacing.s2)
                .padding(.vertical, Spacing.s2)
        }
        .background(Theme.sidebar)
        // Hairline between the sidebar and the page (the header draws its own segment above).
        .overlay(alignment: .trailing) { Theme.sidebarBorder.frame(width: 1) }
    }

    private func item(
        _ route: Route?, _ title: String.LocalizationValue, symbol: Icon, shortcut: String? = nil, badge: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                SidebarRow(
                    String(localized: title), symbol: symbol, isSelected: route != nil && navigator.route == route,
                    shortcut: shortcut)
                if badge > 0 {
                    Text(verbatim: "\(badge)").font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sidebarItemBackground(isSelected: route != nil && navigator.route == route)
    }

    private func pageRow(_ page: PageSummary, depth: Int, children: [PageNode]) -> some View {
        DesktopPageRow(page: page, depth: depth, hasChildren: !children.isEmpty, navigator: navigator, expandable: false)
    }
}

private struct DesktopTree: View {
    let nodes: [PageNode]
    let depth: Int
    @Bindable var navigator: Navigator

    var body: some View {
        ForEach(nodes) { node in
            DesktopPageRow(page: node.page, depth: depth, hasChildren: !node.children.isEmpty, navigator: navigator, expandable: true)
            if navigator.expanded.contains(node.id) {
                if node.children.isEmpty {
                    Text("app:sidebar.noPagesInside")
                        .font(.hk(.md))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.leading, CGFloat(depth + 1) * Spacing.s3_5 + Spacing.s10)
                        .frame(height: 28)
                } else {
                    DesktopTree(nodes: node.children, depth: depth + 1, navigator: navigator)
                }
            }
        }
    }
}

private struct DesktopPageRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorTone) private var colorTone
    let page: PageSummary
    let depth: Int
    let hasChildren: Bool
    @Bindable var navigator: Navigator
    let expandable: Bool

    var body: some View {
        let selected = navigator.route == .page(page.id)
        SidebarRow(
            page.title, icon: page.icon, depth: depth, hasChildren: hasChildren,
            isExpanded: expandable ? expansion : nil, isSelected: selected
        ) {
            PageRowMenu(page: page, navigator: navigator)
            SidebarIconButton("app:page.addInside", symbol: .plus) { navigator.newPage(parentId: page.id) }
        }
        .contentShape(.rect)
        .onTapGesture { navigator.open(page.id) }
        .sidebarItemBackground(
            isSelected: selected || indicator == .inside, highlight: indicator == .inside ? colorTone.selectionFill : nil
        )
        .overlay(alignment: indicator == .before ? .top : .bottom) {
            if indicator == .before || indicator == .after {
                colorTone.fill.frame(height: 2).clipShape(.capsule).padding(.leading, CGFloat(depth) * Spacing.s3_5 + Spacing.s2)
                    .padding(.trailing, Spacing.s2)
            }
        }
        .onDrag {
            navigator.draggingPageID = page.id
            return NSItemProvider(object: page.id as NSString)
        }
        .onDrop(of: [.plainText], delegate: PageRowDropDelegate(target: page.id, navigator: navigator, model: model))
        .contextMenu { PageActions(page: page, navigator: navigator) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("page-row-\(page.title)")
        // Outline level for VoiceOver (and UI tests): "level 1" at the top, +1 per nesting.
        .accessibilityValue(expandable ? "level \(depth + 1)" : "")
    }

    private var indicator: DropZone? {
        navigator.dropIndicator?.pageID == page.id ? navigator.dropIndicator?.zone : nil
    }

    private var expansion: Binding<Bool> {
        Binding(
            get: { navigator.expanded.contains(page.id) },
            set: { open in if open { navigator.expanded.insert(page.id) } else { navigator.expanded.remove(page.id) } }
        )
    }
}

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

/// "app:sidebar.favorites" / "app:sidebar.private" label with optional hover-revealed trailing buttons.
private struct SectionTitle<Trailing: View>: View {
    let title: LocalizedStringKey
    let trailing: Trailing
    @State private var hovering = false

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            SidebarSectionHeader(title)
            Spacer()
            trailing.opacity(hovering ? 1 : 0)
        }
        .padding(.leading, Spacing.s3_5)
        .padding(.trailing, Spacing.s2_5)
        .padding(.top, Spacing.s3_5)
        .frame(height: 40, alignment: .bottom)
        .padding(.bottom, Spacing.s0_5)
        .contentShape(.rect)
        .onHover { hovering = $0 }
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
                Text(verbatim: model.workspace?.name ?? "Hikki")  // the user's workspace name
            }
        } label: {
            SidebarFooterLabel(title: model.workspace?.name ?? "Hikki", subtitle: location) {
                WorkspaceBadge(initial: model.workspace?.initial ?? "H", icon: model.workspace?.icon, size: Size.iconButton + Spacing.s1)
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
    @Environment(\.colorTone) private var colorTone

    var body: some View {
        // Mac/iPad: no List selection — the system paints it in its own accent (blue), which an app can't
        // recolour at runtime. Rows are buttons with a grey pill instead, icons in the colour tone (Apple Music).
        List(selection: wideSidebar ? .constant(nil) : $navigator.sidebarSelection) {
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
                    Text("app:sidebar.favorites")
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
                // No "+" here: New page sits in the toolbar on every platform.
                Text("app:sidebar.private")
            }

            Section {
                SidebarDestination(route: .trash, navigator: navigator, wide: wideSidebar) {
                    NativeSymbolLabel("app:nav.trash", icon: .trash)
                }
                .badge(model.trash.count)
            }
        }
        .listStyle(.sidebar)
        // Sidebar icons in the colour tone (the system would use its own accent).
        // `.fixed`: `.preferred` lets macOS swap in the system accent.
        .listItemTint(.fixed(colorTone.fill))
        // EXPERIMENT: Mac/iPad keep the system sidebar material, with the workspace at the bottom (Apple Music
        // puts the account there); iPhone keeps its tinted list and nav-bar menu.
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

    private func row(_ node: PageNode, chevron: Binding<Bool>?) -> some View {
        SidebarDestination(route: .page(node.id), navigator: navigator, wide: wide, reservesChevron: false) {
            if wide {
                // The chevron's slot comes first; other rows reserve the same slot (SidebarDestination), so every
                // icon lines up and the chevron stays inside the selection.
                HStack(spacing: Spacing.s0) {
                    DisclosureChevron(isExpanded: chevron)
                    NativePageLabel(page: node.page)
                }
                .padding(.leading, CGFloat(depth) * Spacing.s3_5)
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
    /// Rows without their own chevron leave its slot empty, so icons line up with tree rows.
    var reservesChevron = true
    @ViewBuilder let label: Label
    @Environment(\.colorTone) private var colorTone
    @Environment(\.self) private var environment

    var body: some View {
        if wide {
            let selected = showsSelection && navigator.route == route
            Button {
                if let id = route.pageID { navigator.open(id) } else { navigator.go(route) }
            } label: {
                label
                    .padding(.leading, reservesChevron ? Spacing.s3_5 : 0)
                    // A little taller than the system default (~32pt rows, like Apple Music).
                    .padding(.vertical, Spacing.s1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.s2)
                    .contentShape(.rect)
                    // On the tone's fill: title and symbol switch to its on-fill colour.
                    .environment(\.sidebarRowSelected, selected)
                    .foregroundStyle(selected ? colorTone.onFill : Theme.foreground)
                    .fontWeight(selected ? .semibold : nil)
            }
            .buttonStyle(.plain)
            // The selection in the colour tone, drawn behind the row's content and flat: as a list row
            // background the sidebar rendered it raised, with a shadow.
            .background {
                // Resolved to a concrete colour: the tone's dynamic (light/dark) colour got the active sidebar's
                // vibrancy — a lighter band on top, like a raised button. A resolved colour draws flat.
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(selected ? Color(colorTone.fill.resolve(in: environment)) : .clear)
            }
            // The padding moved inside the button for the pill; pull it back so content keeps its place.
            .padding(.horizontal, -Spacing.s2)
            .listRowBackground(Color.clear)
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            NavigationLink(value: route) { label }
        }
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
                        .foregroundStyle(selected ? AnyShapeStyle(colorTone.onFill) : AnyShapeStyle(.secondary))
                        .frame(width: Spacing.s3_5, height: Size.iconButtonSm)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded.wrappedValue ? "app:sidebar.collapse" : "app:sidebar.expand")
            } else {
                Color.clear.frame(width: Spacing.s3_5, height: Size.iconButtonSm)
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
            icon.glyph.frame(width: Size.sidebarIcon + Spacing.s1)
                // Explicit, so neither the system accent nor list tinting replaces the colour tone; on the
                // selection it takes the row's on-fill colour.
                .foregroundStyle(selected ? colorTone.onFill : colorTone.fill)
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
                Text("app:page.untitled").foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            } else {
                Text(verbatim: page.title)  // the page's own title
            }
        } icon: {
            Group {
                if page.icon == nil, selected {
                    // The default page glyph is a muted grey; on the tone's fill it takes the row's white.
                    IconView(.fileText, size: TextSize.base.rawValue * 0.95).foregroundStyle(colorTone.onFill)
                } else {
                    PageIcon(page.icon, size: TextSize.base.rawValue)
                }
            }
            .frame(width: Size.sidebarIcon + Spacing.s1)
        }
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
        let url = PageLink.url(for: page.id)
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
                .safeAreaInset(edge: .top) {
                    GlassSearchField("app:nav.search", shortcut: "⌘K") { navigator.isSearching = true }
                        .accessibilityIdentifier("sidebar-search")
                        .padding(.horizontal, Spacing.s3)
                        .padding(.bottom, Spacing.s1)
                }
                .safeAreaInset(edge: .bottom) {
                    WorkspaceSwitcher(navigator: navigator)
                        .padding(.horizontal, Spacing.s2)
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
