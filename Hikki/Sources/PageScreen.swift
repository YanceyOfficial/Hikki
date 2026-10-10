import HikkiCore
import HikkiUI
import SwiftUI

/// A page: the shared editor web view plus Notion-style chrome (breadcrumbs, edited time, favorite, ⋯).
struct PageScreen: View {
    @Environment(AppModel.self) private var model
    let pageID: String
    let editor: EditorController
    let navigator: Navigator

    var body: some View {
        let page = model.tree.page(pageID)
        EditorView(controller: editor)
            .ignoresSafeArea(.container, edges: .bottom)
            .background(Theme.background)
            .navigationTitle(page.map { $0.title.isEmpty ? String(localized: "Untitled") : $0.title } ?? "")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .toolbar(removing: .title)
            #endif
            .toolbar {
                ToolbarItem(placement: breadcrumbPlacement) {
                    Breadcrumbs(path: model.tree.path(to: pageID)) { navigator.open($0) }
                }
                if let page {
                    ToolbarItemGroup(placement: .primaryAction) {
                        #if os(macOS)
                            TimelineView(.periodic(from: .now, by: 60)) { _ in
                                Text("Edited \(page.updatedAt, format: .relative(presentation: .named))")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.mutedText)
                            }
                        #endif
                        Button(page.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                               systemImage: page.isFavorite ? "star.fill" : "star") {
                            model.setFavorite(!page.isFavorite, id: page.id)
                        }
                        .tint(page.isFavorite ? .yellow : nil)
                        .accessibilityIdentifier("favorite-toggle")
                        Menu("More", systemImage: "ellipsis") {
                            PageActions(page: page, navigator: navigator)
                            Divider()
                            Text("Edited \(page.updatedAt, format: .relative(presentation: .named))")
                        }
                        .accessibilityIdentifier("page-more")
                    }
                }
            }
    }

    private var breadcrumbPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .principal
        #else
            .navigation
        #endif
    }
}

/// "📄 Parent / 📄 Child" — every crumb but the last navigates.
private struct Breadcrumbs: View {
    let path: [PageSummary]
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Text("/").font(.system(size: 13)).foregroundStyle(Theme.mutedText).padding(.horizontal, 2)
                }
                switch crumb {
                case .ellipsis:
                    Text("…").font(.system(size: 13)).foregroundStyle(Theme.mutedText)
                case .page(let page, let isLast):
                    Button { if !isLast { onSelect(page.id) } } label: {
                        HStack(spacing: 4) {
                            if page.icon != nil { PageIcon(page.icon, size: 13) }
                            Text(page.title.isEmpty ? String(localized: "Untitled") : page.title)
                                .font(.system(size: 13, weight: isLast ? .medium : .regular))
                                .foregroundStyle(isLast ? Theme.text : Theme.secondaryText)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(HoverHighlightStyle())
                    .disabled(isLast)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("breadcrumbs")
    }

    private enum Crumb {
        case page(PageSummary, isLast: Bool)
        case ellipsis
    }

    /// Long paths collapse the middle, like Notion: first / … / parent / page.
    private var visible: [Crumb] {
        let crumbs = path.enumerated().map { Crumb.page($1, isLast: $0 == path.count - 1) }
        guard crumbs.count > 3 else { return crumbs }
        return [crumbs[0], .ellipsis] + crumbs.suffix(2)
    }
}
