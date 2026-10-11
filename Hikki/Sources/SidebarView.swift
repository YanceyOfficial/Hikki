import HikkiCore
import HikkiUI
import SwiftUI

/// Mac/iPad get a custom, Notion-like sidebar (full control over density and highlight);
/// iPhone keeps a List so rows push the page with native navigation.
struct SidebarView: View {
    @Bindable var navigator: Navigator
    let customChrome: Bool

    var body: some View {
        if customChrome {
            DesktopSidebar(navigator: navigator)
        } else {
            PhoneSidebar(navigator: navigator)
        }
    }
}

// MARK: - Mac / iPad

private struct DesktopSidebar: View {
    @Environment(AppModel.self) private var model
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
                    .background(privateTargeted ? Theme.selection : .clear, in: .rect(cornerRadius: Radius.md))
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
        .sidebarItemBackground(isSelected: selected || indicator == .inside, highlight: indicator == .inside ? Theme.selection : nil)
        .overlay(alignment: indicator == .before ? .top : .bottom) {
            if indicator == .before || indicator == .after {
                Theme.primary.frame(height: 2).clipShape(.capsule).padding(.leading, CGFloat(depth) * Spacing.s3_5 + Spacing.s2)
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
                WorkspaceBadge(initial: model.workspace?.initial ?? "H", size: Size.iconButton + Spacing.s1)
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
    @State private var renaming = false

    var body: some View {
        List(selection: $navigator.sidebarSelection) {
            Section {
                Button {
                    navigator.isSearching = true
                } label: {
                    SidebarRow(String(localized: "app:nav.search"), symbol: .magnifyingGlass)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar-search")
                NavigationLink(value: Route.home) {
                    SidebarRow(String(localized: "app:nav.home"), symbol: .house)
                }
            }

            if !model.tree.favorites.isEmpty {
                Section {
                    ForEach(model.tree.favorites) { page in
                        NavigationLink(value: Route.page(page.id)) {
                            SidebarRow(page.title, icon: page.icon)
                        }
                        .contextMenu { PageActions(page: page, navigator: navigator) }
                    }
                } header: {
                    SidebarSectionHeader("app:sidebar.favorites")
                }
            }

            Section {
                if model.tree.roots.isEmpty {
                    Button {
                        navigator.newPage()
                    } label: {
                        SidebarRow(String(localized: "app:sidebar.addPage"), symbol: .plus)
                    }
                    .buttonStyle(.plain)
                }
                PhoneTree(nodes: model.tree.roots, depth: 0, navigator: navigator)
            } header: {
                HStack {
                    SidebarSectionHeader("app:sidebar.private")
                    Spacer()
                    SidebarIconButton("app:page.new", symbol: .plus) { navigator.newPage() }
                        .accessibilityIdentifier("new-page-section")
                }
            }

            Section {
                NavigationLink(value: Route.trash) {
                    SidebarRow(String(localized: "app:nav.trash"), symbol: .trash)
                }
                .badge(model.trash.count)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
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
                // The workspace menu (iPhone has no sidebar header).
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

private struct PhoneTree: View {
    let nodes: [PageNode]
    let depth: Int
    @Bindable var navigator: Navigator

    var body: some View {
        ForEach(nodes) { node in
            NavigationLink(value: Route.page(node.id)) {
                SidebarRow(
                    node.page.title, icon: node.page.icon, depth: depth, hasChildren: !node.children.isEmpty,
                    isExpanded: expansion(node.id))
            }
            .contextMenu { PageActions(page: node.page, navigator: navigator) }
            .accessibilityIdentifier("page-row-\(node.page.title)")
            if navigator.expanded.contains(node.id), !node.children.isEmpty {
                PhoneTree(nodes: node.children, depth: depth + 1, navigator: navigator)
            }
        }
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(
            get: { navigator.expanded.contains(id) },
            set: { open in if open { navigator.expanded.insert(id) } else { navigator.expanded.remove(id) } }
        )
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
