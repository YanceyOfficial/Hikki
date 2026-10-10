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
        EditorView(controller: editor)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle(page.map { $0.title.isEmpty ? String(localized: "Untitled") : $0.title } ?? "")
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
                        Text("Edited \(page.updatedAt, format: .relative(presentation: .named))")
                            .font(.hk(.md))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                    }
                    .padding(.trailing, Spacing.s1_5)
                    FavoriteButton(page: page)
                    PageMoreMenu(page: page, navigator: navigator)
                }
            case .home:
                barTitle("Home", systemImage: "house")
                Spacer()
            case .trash:
                barTitle("Trash", systemImage: "trash")
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.s3)
        .frame(height: 44)
        .background(Theme.background)
    }

    private func barTitle(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.hk(.md, .medium))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, Spacing.s1_5)
    }
}

struct FavoriteButton: View {
    @Environment(AppModel.self) private var model
    let page: PageSummary

    var body: some View {
        BarIconButton(page.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: page.isFavorite ? "star.fill" : "star",
                      tint: page.isFavorite ? .yellow : nil) {
            model.setFavorite(!page.isFavorite, id: page.id)
        }
        .accessibilityIdentifier("favorite-toggle")
    }
}

struct PageMoreMenu: View {
    let page: PageSummary
    let navigator: Navigator

    var body: some View {
        Menu {
            PageActions(page: page, navigator: navigator)
            Divider()
            Text("Edited \(page.updatedAt, format: .relative(presentation: .named))")
        } label: {
            Image(systemName: "ellipsis")
                .font(.hk(.base))
                .foregroundStyle(Theme.subtleForeground)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(HoverHighlightStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
        .accessibilityIdentifier("page-more")
    }
}
