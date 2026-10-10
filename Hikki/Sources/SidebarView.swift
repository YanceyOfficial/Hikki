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
            WorkspaceHeader()
            SidebarNavBar([
                .init(id: "home", title: String(localized: "Home"), systemImage: "house", isSelected: navigator.route == .home) {
                    navigator.go(.home)
                },
                .init(id: "trash", title: String(localized: "Trash"), systemImage: "trash", isSelected: navigator.route == .trash) {
                    navigator.go(.trash)
                },
            ]) {
                BarIconButton("Search (⌘K)", systemImage: "magnifyingglass") { navigator.isSearching = true }
                    .accessibilityIdentifier("sidebar-search")
            }
            .padding(.horizontal, Spacing.s2)
            .padding(.top, Spacing.s3)
            .padding(.bottom, Spacing.s1)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.px) {
                    if !model.tree.favorites.isEmpty {
                        SectionTitle("Favorites")
                        ForEach(model.tree.favorites) { page in
                            pageRow(page, depth: 0, children: [])
                        }
                    }

                    SectionTitle("Private") {
                        SidebarIconButton("New Page", systemImage: "plus") { navigator.newPage() }
                            .accessibilityIdentifier("new-page-section")
                    }
                    .background(privateTargeted ? Theme.selection : .clear, in: .rect(cornerRadius: Radius.md))
                    .onDrop(
                        of: [.plainText], delegate: SectionDropDelegate(navigator: navigator, model: model, isTargeted: $privateTargeted))
                    if model.tree.roots.isEmpty {
                        item(Route?.none, "Add a page", systemImage: "plus") { navigator.newPage() }
                    }
                    DesktopTree(nodes: model.tree.roots, depth: 0, navigator: navigator)
                }
                .padding(.vertical, Spacing.s1_5)
            }
            .scrollIndicators(.never)

            SidebarActionPill("New page", systemImage: "square.and.pencil", shortcut: "⌘N") { navigator.newPage() }
                .accessibilityIdentifier("new-page")
                .padding(Spacing.s3)
        }
        .background(Theme.sidebar)
        #if os(macOS)
            .ignoresSafeArea(.container, edges: .top)
        #else
            .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func item(
        _ route: Route?, _ title: String.LocalizationValue, systemImage: String, shortcut: String? = nil, badge: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                SidebarRow(
                    String(localized: title), systemImage: systemImage, isSelected: route != nil && navigator.route == route,
                    shortcut: shortcut)
                if badge > 0 {
                    Text("\(badge)").font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
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
                    Text("No pages inside")
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
            SidebarIconButton("Add a page inside", systemImage: "plus") { navigator.newPage(parentId: page.id) }
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

/// Drop onto the "Private" header: move the dragged page to the end of the top level.
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

/// "Favorites" / "Private" label with optional hover-revealed trailing buttons.
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
private struct WorkspaceHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.chromeMetrics) private var metrics

    var body: some View {
        HStack(spacing: Spacing.s0_5) {
            Color.clear.frame(width: max(0, metrics.leadingInset - Spacing.s2))  // traffic lights
            Menu {
                ShareLink("Export Logs", items: model.exportableFiles)
            } label: {
                HStack(spacing: Spacing.s2) {
                    Text("H")
                        .font(.hk(.x2s, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Theme.primary.gradient, in: .rect(cornerRadius: Radius.sm))
                    Text("Hikki")
                        .font(.hk(.sm, .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.hk(.x2s, .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .padding(.horizontal, Spacing.s1_5)
                .padding(.vertical, Spacing.s1)
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(HoverHighlightStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer(minLength: 4)
        }
        .padding(.horizontal, Spacing.s2)
        .frame(height: metrics.barHeight)
    }
}

// MARK: - iPhone

private struct PhoneSidebar: View {
    @Environment(AppModel.self) private var model
    @Bindable var navigator: Navigator

    var body: some View {
        List(selection: $navigator.sidebarSelection) {
            Section {
                Button {
                    navigator.isSearching = true
                } label: {
                    SidebarRow(String(localized: "Search"), systemImage: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar-search")
                NavigationLink(value: Route.home) {
                    SidebarRow(String(localized: "Home"), systemImage: "house")
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
                    SidebarSectionHeader("Favorites")
                }
            }

            Section {
                if model.tree.roots.isEmpty {
                    Button {
                        navigator.newPage()
                    } label: {
                        SidebarRow(String(localized: "Add a page"), systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                }
                PhoneTree(nodes: model.tree.roots, depth: 0, navigator: navigator)
            } header: {
                HStack {
                    SidebarSectionHeader("Private")
                    Spacer()
                    SidebarIconButton("New Page", systemImage: "plus") { navigator.newPage() }
                        .accessibilityIdentifier("new-page-section")
                }
            }

            Section {
                NavigationLink(value: Route.trash) {
                    SidebarRow(String(localized: "Trash"), systemImage: "trash")
                }
                .badge(model.trash.count)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .navigationTitle("Hikki")
        .toolbar {
            ToolbarItem {
                Button("New Page", systemImage: "square.and.pencil") { navigator.newPage() }
                    .accessibilityIdentifier("new-page")
            }
            ToolbarItem {
                Menu("More", systemImage: "ellipsis.circle") {
                    ShareLink("Export Logs", items: model.exportableFiles)
                }
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
            Image(systemName: "ellipsis")
                .font(.hk(.xs, .semibold))
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(HoverHighlightStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Delete, favorite and more…")
    }
}

/// Shared page actions for the ⋯ menu, context menus and the page bar.
struct PageActions: View {
    @Environment(AppModel.self) private var model
    let page: PageSummary
    let navigator: Navigator

    var body: some View {
        Button(page.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: page.isFavorite ? "star.slash" : "star") {
            model.setFavorite(!page.isFavorite, id: page.id)
        }
        Button("Open in New Tab", systemImage: "plus.square.on.square") { navigator.openInNewTab(.page(page.id)) }
        Button("Add a Page Inside", systemImage: "plus") { navigator.newPage(parentId: page.id) }
        Divider()
        Button("Move to Trash", systemImage: "trash", role: .destructive) { model.moveToTrash(id: page.id) }
    }
}
