import HikkiCore
import HikkiUI
import SwiftUI

/// The editor for one page. On iPhone it also owns the nav-bar toolbar; wider layouts use `PageBar`.
struct PageScreen: View {
    @Environment(AppModel.self) private var model
    let pageID: String
    let editor: EditorController
    let navigator: Navigator
    let phoneToolbar: Bool

    var body: some View {
        let page = model.tree.page(pageID)
        // The page runs under the window toolbar (Photos-style glass); the toolbar's height becomes the
        // editor's top inset so the first line still starts below it.
        GeometryReader { proxy in
            EditorView(controller: editor, topInset: proxy.safeAreaInsets.top)
                .ignoresSafeArea(.container, edges: [.top, .bottom])
        }
        .navigationTitle(page.map { $0.title.isEmpty ? String(localized: "app:page.untitled") : $0.title } ?? "")
        #if os(macOS)
            .navigationSubtitle(
                page.map { Text("app:page.edited \($0.updatedAt, format: .relative(presentation: .named))") } ?? Text(verbatim: ""))
        #endif
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phoneToolbar, let page {
                    ToolbarItemGroup(placement: .primaryAction) {
                        FavoriteButton(page: page)
                        PageMoreMenu(page: page, navigator: navigator)
                    }
                }
            }
        #endif
    }
}

/// Notion's second row: breadcrumbs on the left; edited time, favorite and ⋯ on the right. Flat, no glass.
struct PageBar: View {
    @Environment(AppModel.self) private var model
    let route: Route
    let navigator: Navigator

    var body: some View {
        HStack(spacing: Spacing.s1) {
            switch route {
            case .page(let id):
                Breadcrumbs(model.tree.path(to: id).map { Crumb(id: $0.id, title: $0.title, icon: $0.icon) }) { navigator.open($0) }
                Spacer(minLength: 8)
                if let page = model.tree.page(id) {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text("app:page.edited \(page.updatedAt, format: .relative(presentation: .named))")
                            .font(.hk(.md))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                    }
                    .padding(.trailing, Spacing.s1_5)
                    FavoriteButton(page: page)
                    PageMoreMenu(page: page, navigator: navigator)
                }
            case .home:
                barTitle("app:nav.home", symbol: .house)
                Spacer()
            case .trash:
                barTitle("app:nav.trash", symbol: .trash)
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.s3)
        .frame(height: 44)
        .background(Theme.background)
    }

    private func barTitle(_ title: LocalizedStringKey, symbol: Icon) -> some View {
        IconLabel(title, icon: symbol)
            .font(.hk(.md, .medium))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, Spacing.s1_5)
    }
}

struct FavoriteButton: View {
    @Environment(AppModel.self) private var model
    let page: PageSummary
    /// In a window toolbar: a plain button, so the system draws it inside the group's glass.
    var toolbar = false

    var body: some View {
        if toolbar {
            Button {
                model.setFavorite(!page.isFavorite, id: page.id)
            } label: {
                IconLabel(page.isFavorite ? "app:page.unfavorite" : "app:page.favorite", icon: page.isFavorite ? .starFill : .star)
            }
            .foregroundStyle(page.isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.primary))
            .help(page.isFavorite ? "app:page.unfavorite" : "app:page.favorite")
            .accessibilityIdentifier("favorite-toggle")
        } else {
            barButton
        }
    }

    private var barButton: some View {
        BarIconButton(
            page.isFavorite ? "app:page.unfavorite" : "app:page.favorite",
            symbol: page.isFavorite ? .starFill : .star,
            tint: page.isFavorite ? .yellow : nil
        ) {
            model.setFavorite(!page.isFavorite, id: page.id)
        }
        .accessibilityIdentifier("favorite-toggle")
    }
}

struct PageMoreMenu: View {
    let page: PageSummary
    let navigator: Navigator
    /// In a window toolbar: a plain menu button, drawn by the system inside the group's glass.
    var toolbar = false

    var body: some View {
        if toolbar {
            Menu {
                items
            } label: {
                IconLabel("app:common.more", icon: .dotsThree)
            }
            .menuIndicator(.hidden)
            .help("app:common.more")
            .accessibilityIdentifier("page-more")
        } else {
            barMenu
        }
    }

    @ViewBuilder private var items: some View {
        PageActions(page: page, navigator: navigator)
        Divider()
        Text("app:page.edited \(page.updatedAt, format: .relative(presentation: .named))")
    }

    private var barMenu: some View {
        Menu {
            items
        } label: {
            IconView(.dotsThree, size: TextSize.base.rawValue)
                .foregroundStyle(Theme.subtleForeground)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(HoverHighlightStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("app:common.more")
        .accessibilityIdentifier("page-more")
    }
}
