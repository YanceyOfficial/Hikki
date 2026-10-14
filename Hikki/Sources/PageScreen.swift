import HikkiCore
import HikkiUI
import SwiftUI

/// The editor for one page. On iPhone it also owns the nav-bar toolbar; wider layouts use the window toolbar.
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
        .navigationTitle(page.map { Self.title($0) } ?? "")
        #if os(macOS)
            // Breadcrumbs, natively: the path in the subtitle ("Parent › Child · Edited …")…
            .navigationSubtitle(page.map(subtitle) ?? Text(verbatim: ""))
        #endif
        // …and the title's menu jumps to any parent (as Finder's and Xcode's titles do).
        .toolbarTitleMenu {
            ForEach(ancestors.reversed()) { parent in
                Button {
                    navigator.open(parent.id)
                } label: {
                    Text(verbatim: (parent.icon.map { "\($0) " } ?? "") + Self.title(parent))
                }
            }
        }
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phoneToolbar, let page {
                    if page.isLocked {
                        ToolbarItem(placement: .primaryAction) { LockIndicator(page: page) }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        FavoriteButton(page: page)
                        PageMoreMenu(page: page, navigator: navigator, editor: editor)
                    }
                }
            }
        #endif
    }

    /// Parents of the page, nearest last (root first).
    private var ancestors: [PageSummary] { model.tree.path(to: pageID).dropLast() }

    private func subtitle(_ page: PageSummary) -> Text {
        let edited = Text("app:page.edited \(page.updatedAt, format: .relative(presentation: .named))")
        guard !ancestors.isEmpty else { return edited }
        // The page titles, shown as-is.
        return Text(verbatim: ancestors.map(Self.title).joined(separator: " › ") + " · ") + edited
    }

    private static func title(_ page: PageSummary) -> String {
        page.title.isEmpty ? String(localized: "app:page.untitled") : page.title
    }
}

/// A lock in the toolbar while the page is locked; pressing it unlocks (the page is read-only meanwhile).
/// Placed conditionally by the toolbar (a toolbar item that draws nothing made macOS lay the toolbar out
/// without end).
struct LockIndicator: View {
    @Environment(AppModel.self) private var model
    let page: PageSummary
    /// In a window toolbar: a plain button, so the system draws it inside the group's glass.
    var toolbar = false

    var body: some View {
        if toolbar {
            Button {
                model.setLocked(false, id: page.id)
            } label: {
                IconLabel("app:page.locked", icon: .lockSimple)
            }
            .help("app:page.unlock")
            .accessibilityIdentifier("lock-indicator")
        } else {
            BarIconButton("app:page.locked", symbol: .lockSimple, tint: nil) {
                model.setLocked(false, id: page.id)
            }
            .accessibilityIdentifier("lock-indicator")
        }
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
    /// The editor showing this page: "Find in Page" (the only way to find on a phone without a keyboard).
    var editor: EditorController?
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
        if let editor {
            Button {
                editor.find(.find)
            } label: {
                IconLabel("app:find.inPage", icon: .magnifyingGlass)
            }
            .accessibilityIdentifier("find-in-page")
            Divider()
        }
        PageActions(page: page, navigator: navigator)
        Divider()
        #if os(iOS)
            // iPhone: the inspector (outline, info, calendar) is a sheet, opened from here.
            if !toolbar {
                Button {
                    navigator.isShowingInspector = true
                } label: {
                    IconLabel("app:inspector.toggle", icon: .columnsPlusRight)
                }
                .accessibilityIdentifier("open-inspector")
                Divider()
            }
        #endif
        Text("app:page.edited \(page.updatedAt, format: .relative(presentation: .named))")
        if let info = editor?.pageInfo, info.docId == page.id {
            Text("app:page.stats \(info.words.formatted()) \(info.characters.formatted())")
        }
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
