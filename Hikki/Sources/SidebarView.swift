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

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader()
            SidebarNavBar([
                .init(id: "home", title: String(localized: "Home"), systemImage: "house", isSelected: navigator.route == .home) { navigator.go(.home) },
                .init(id: "trash", title: String(localized: "Trash"), systemImage: "trash", isSelected: navigator.route == .trash) { navigator.go(.trash) },
            ]) {
                BarIconButton("Search (⌘K)", systemImage: "magnifyingglass") { navigator.isSearching = true }
                    .accessibilityIdentifier("sidebar-search")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
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
                    if model.tree.roots.isEmpty {
                        item(Route?.none, "Add a page", systemImage: "plus") { navigator.newPage() }
                    }
                    DesktopTree(nodes: model.tree.roots, depth: 0, navigator: navigator)
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)

            SidebarActionPill("New page", systemImage: "square.and.pencil", shortcut: "⌘N") { navigator.newPage() }
                .accessibilityIdentifier("new-page")
                .padding(12)
        }
        .background(Theme.sidebar)
        #if os(macOS)
        .ignoresSafeArea(.container, edges: .top)
        #else
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func item(_ route: Route?, _ title: String.LocalizationValue, systemImage: String, shortcut: String? = nil, badge: Int = 0,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                SidebarRow(String(localized: title), systemImage: systemImage, isSelected: route != nil && navigator.route == route,
                           shortcut: shortcut)
                if badge > 0 {
                    Text("\(badge)").font(.system(size: 12)).foregroundStyle(Theme.mutedText)
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
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.mutedText)
                        .padding(.leading, CGFloat(depth + 1) * 14 + 42)
                        .frame(height: 28)
                } else {
                    DesktopTree(nodes: node.children, depth: depth + 1, navigator: navigator)
                }
            }
        }
    }
}

private struct DesktopPageRow: View {
    let page: PageSummary
    let depth: Int
    let hasChildren: Bool
    @Bindable var navigator: Navigator
    let expandable: Bool

    var body: some View {
        let selected = navigator.route == .page(page.id)
        SidebarRow(page.title, icon: page.icon, depth: depth, hasChildren: hasChildren,
                   isExpanded: expandable ? expansion : nil, isSelected: selected) {
            PageRowMenu(page: page, navigator: navigator)
            SidebarIconButton("Add a page inside", systemImage: "plus") { navigator.newPage(parentId: page.id) }
        }
        .contentShape(.rect)
        .onTapGesture { navigator.open(page.id) }
        .sidebarItemBackground(isSelected: selected)
        .contextMenu { PageActions(page: page, navigator: navigator) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("page-row-\(page.title)")
    }

    private var expansion: Binding<Bool> {
        Binding(
            get: { navigator.expanded.contains(page.id) },
            set: { open in if open { navigator.expanded.insert(page.id) } else { navigator.expanded.remove(page.id) } }
        )
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
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.top, 14)
        .frame(height: 40, alignment: .bottom)
        .padding(.bottom, 2)
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }
}

/// Top of the sidebar on Mac/iPad: workspace menu next to the traffic lights.
private struct WorkspaceHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            #if os(macOS)
                Color.clear.frame(width: 68) // traffic lights
            #endif
            Menu {
                ShareLink("Export Logs", items: model.exportableFiles)
            } label: {
                HStack(spacing: 7) {
                    Text("H")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Theme.accent.gradient, in: .rect(cornerRadius: 5))
                    Text("Hikki")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.mutedText)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(HoverHighlightStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .frame(height: TabStrip<EmptyView>.height)
    }
}

// MARK: - iPhone

private struct PhoneSidebar: View {
    @Environment(AppModel.self) private var model
    @Bindable var navigator: Navigator

    var body: some View {
        List(selection: $navigator.sidebarSelection) {
            Section {
                Button { navigator.isSearching = true } label: {
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
                    Button { navigator.newPage() } label: {
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
                SidebarRow(node.page.title, icon: node.page.icon, depth: depth, hasChildren: !node.children.isEmpty,
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.mutedText)
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
