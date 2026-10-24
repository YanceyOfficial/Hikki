#if os(iOS)
    import HikkiCore
    import HikkiUI
    import SwiftUI

    /// The iPhone's side drawer (Notion's), behind Home's ☰ or a swipe from the left (`SideDrawer`, HikkiUI): the
    /// workspace and a search field on top, favorites and the page tree — each row with its chevron, icon and title, +
    /// for a page inside and ⋯ for the page's actions — then "Add a page", and All pages, Trash and Settings fixed at the
    /// bottom. Anything picked closes the drawer and opens through the navigator.
    struct PhoneDrawer: View {
        @Environment(AppModel.self) private var model
        @Bindable var navigator: Navigator
        /// Slides the drawer shut (the caller animates it).
        let close: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.s0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.s5) {
                        if !model.tree.favorites.isEmpty {
                            section("app:sidebar.favorites") {
                                ForEach(model.tree.favorites) { page in
                                    DrawerPageRow(page: page, depth: 0, isExpanded: nil, navigator: navigator, close: close)
                                }
                            }
                        }
                        section("app:home.pages") {
                            DrawerPageTree(nodes: model.tree.roots, depth: 0, navigator: navigator, close: close)
                            DrawerPlace(title: "app:sidebar.addPage", icon: .plus, identifier: "drawer-new-page", inTree: true) {
                                pick { navigator.newPage() }
                            }
                        }
                    }
                    .padding(.vertical, Spacing.s2)
                }
                .scrollIndicators(.hidden)
                VStack(alignment: .leading, spacing: Spacing.s0) {
                    DrawerPlace(title: "app:home.allPages", icon: .house, identifier: "drawer-all-pages") {
                        pick { navigator.go(.home) }
                    }
                    DrawerPlace(title: "app:nav.trash", icon: .trash, identifier: "drawer-trash") {
                        pick { navigator.go(.trash) }
                    }
                    DrawerPlace(title: "app:settings.open", icon: .gearSix, identifier: "drawer-settings") {
                        pick { navigator.isShowingSettings = true }
                    }
                }
                .padding(.vertical, Spacing.s2)
                .overlay(alignment: .top) { Theme.sidebarBorder.frame(height: Spacing.px) }
            }
            .background(Theme.sidebar)
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack(spacing: Spacing.s2_5) {
                    WorkspaceBadge(
                        initial: model.workspace?.initial ?? "H", icon: model.workspace?.icon,
                        size: Size.iconButton + Spacing.s0_5)
                    // The user's workspace name.
                    Text(verbatim: model.workspace?.name ?? "Hikki")
                        .font(.hk(.lg, .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .accessibilityIdentifier("drawer-workspace")
                    Spacer(minLength: 0)
                }
                Button {
                    pick { navigator.isSearching = true }
                } label: {
                    HStack(spacing: Spacing.s2) {
                        IconView(.magnifyingGlass, size: TextSize.base.rawValue)
                        Text("app:nav.search").font(.hk(.base))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, Spacing.s3)
                    .frame(height: Size.searchField + Spacing.s1)
                    .background(Theme.sidebarAccent, in: .rect(cornerRadius: Radius.xl))
                    .contentShape(.rect(cornerRadius: Radius.xl))
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("drawer-search")
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s3)
            .padding(.bottom, Spacing.s2)
            .clearOfTopEdge()
        }

        private func section(_ title: LocalizedStringKey, @ViewBuilder rows: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: Spacing.s0) {
                SectionTitle(title).padding(.horizontal, Spacing.s4).padding(.bottom, Spacing.s1)
                rows()
            }
        }

        private func pick(_ action: () -> Void) {
            close()
            action()
        }
    }

    /// A fixed place in the drawer (All pages, Trash, Settings, Add a page): an icon and a name.
    private struct DrawerPlace: View {
        let title: LocalizedStringKey
        let icon: Icon
        let identifier: String
        /// Under the page tree: lined up with the rows' icons, past their chevron slot.
        var inTree = false
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: Spacing.s2_5) {
                    IconView(icon, size: TextSize.lg.rawValue)
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: Size.iconButton)
                    Text(title).font(.hk(.base)).foregroundStyle(Theme.sidebarForeground)
                    Spacer(minLength: 0)
                }
                .padding(.leading, inTree ? Spacing.s2 + Size.iconButton + Spacing.s1 : Spacing.s3)
                .padding(.trailing, Spacing.s3)
                .frame(height: Size.touchRow)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
        }
    }

    /// The page tree as rows: a page's subpages show under it while it is expanded; deeper rows indent.
    private struct DrawerPageTree: View {
        let nodes: [PageNode]
        let depth: Int
        @Bindable var navigator: Navigator
        let close: () -> Void

        var body: some View {
            ForEach(nodes) { node in
                DrawerPageRow(
                    page: node.page, depth: depth, isExpanded: node.children.isEmpty ? nil : expansion(node.id),
                    navigator: navigator, close: close)
                if !node.children.isEmpty, navigator.expanded.contains(node.id) {
                    DrawerPageTree(nodes: node.children, depth: depth + 1, navigator: navigator, close: close)
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

    /// One page: chevron (when it has subpages), icon and title open it; ⋯ holds its actions, + adds a page inside.
    private struct DrawerPageRow: View {
        let page: PageSummary
        let depth: Int
        /// Nil for a page without subpages (no chevron, its slot kept so icons line up).
        let isExpanded: Binding<Bool>?
        let navigator: Navigator
        let close: () -> Void

        var body: some View {
            HStack(spacing: Spacing.s1) {
                Group {
                    if let isExpanded {
                        Button {
                            withAnimation(Motion.easeOut()) { isExpanded.wrappedValue.toggle() }
                        } label: {
                            IconView(.caretRight, size: TextSize.xs.rawValue)
                                .foregroundStyle(Theme.placeholder)
                                .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                                .frame(width: Size.iconButton, height: Size.touchRow)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(isExpanded.wrappedValue ? "app:sidebar.collapse" : "app:sidebar.expand"))
                        .accessibilityIdentifier("page-expand-\(title)")
                    } else {
                        Color.clear.frame(width: Size.iconButton)
                    }
                }
                Button {
                    close()
                    navigator.open(page.id)
                } label: {
                    PageRowLabel(icon: page.icon, title: page.title, nested: depth > 0)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("page-row-\(title)")
            }
            .padding(.leading, Spacing.s2 + CGFloat(depth) * Spacing.s4)
            .padding(.trailing, Spacing.s2)
            // Its actions — Add a page inside among them — on a long press (no ⋯ / + on every row: the tree stays calm).
            .contextMenu { PageActions(page: page, navigator: navigator) }
        }

        private var title: String { page.displayTitle }
    }
#endif
