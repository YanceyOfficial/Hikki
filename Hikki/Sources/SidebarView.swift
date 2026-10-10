import HikkiCore
import HikkiUI
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Bindable var navigator: Navigator

    var body: some View {
        List(selection: $navigator.route) {
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
                            SidebarRow(page.title, icon: page.icon) { PageRowMenu(page: page, navigator: navigator) }
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
                PageTreeRows(nodes: model.tree.roots, depth: 0, navigator: navigator)
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

/// Recursive page rows with disclosure, hover actions and context menu.
private struct PageTreeRows: View {
    let nodes: [PageNode]
    let depth: Int
    @Bindable var navigator: Navigator

    var body: some View {
        ForEach(nodes) { node in
            NavigationLink(value: Route.page(node.id)) {
                SidebarRow(
                    node.page.title,
                    icon: node.page.icon,
                    depth: depth,
                    hasChildren: !node.children.isEmpty,
                    isExpanded: expansion(node.id)
                ) {
                    PageRowMenu(page: node.page, navigator: navigator)
                    SidebarIconButton("Add a page inside", systemImage: "plus") { navigator.newPage(parentId: node.id) }
                }
            }
            .contextMenu { PageActions(page: node.page, navigator: navigator) }
            .accessibilityIdentifier("page-row-\(node.page.title)")

            if navigator.expanded.contains(node.id) {
                if node.children.isEmpty {
                    Text("No pages inside")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.mutedText)
                        .padding(.leading, CGFloat(depth + 1) * 14 + 28)
                        .selectionDisabled()
                } else {
                    PageTreeRows(nodes: node.children, depth: depth + 1, navigator: navigator)
                }
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

/// ⋯ button on a sidebar row.
private struct PageRowMenu: View {
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
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Delete, favorite and more…")
    }
}

/// Shared page actions for the ⋯ menu, context menus and the page toolbar.
struct PageActions: View {
    @Environment(AppModel.self) private var model
    let page: PageSummary
    let navigator: Navigator

    var body: some View {
        Button(page.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: page.isFavorite ? "star.slash" : "star") {
            model.setFavorite(!page.isFavorite, id: page.id)
        }
        Button("Add a Page Inside", systemImage: "plus") { navigator.newPage(parentId: page.id) }
        Divider()
        Button("Move to Trash", systemImage: "trash", role: .destructive) { model.moveToTrash(id: page.id) }
    }
}
