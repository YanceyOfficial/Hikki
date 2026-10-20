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
    #if os(iOS)
        /// The software keyboard is up: the bottom bar steps aside for the formatting bar.
        @State private var keyboardShown = false
        /// An iPhone Duo's vertical bar: the floating bar's buttons go there instead.
        @Environment(\.verticalBarEdge) private var verticalBar
    #endif

    var body: some View {
        let page = model.tree.page(pageID)
        // The page runs under the window toolbar (Photos-style glass); the toolbar's height becomes the
        // editor's top inset so the first line still starts below it.
        GeometryReader { proxy in
            EditorView(controller: editor, topInset: proxy.safeAreaInsets.top, bottomInset: bottomBarInset)
                .ignoresSafeArea(.container, edges: underBars)
        }
        // iPhone: the page shows its own title; the bar keeps only its glass buttons.
        .navigationTitle(phoneToolbar ? "" : page.map { Self.title($0) } ?? "")
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
                        FavoriteButton(page: page, toolbar: true)
                        Button {
                            navigator.pageActionsID = page.id
                        } label: {
                            IconLabel("app:common.more", icon: .dotsThree)
                        }
                        .accessibilityIdentifier("page-more")
                    }
                    if verticalBar != nil {
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button {
                                navigator.toggleInspector(.outline)
                            } label: {
                                IconLabel("app:inspector.outline", icon: .listBullets)
                            }
                            .accessibilityIdentifier("open-inspector")
                            Button {
                                navigator.isAskingAI = true
                            } label: {
                                Label {
                                    Text("app:ai.askPage")
                                } icon: {
                                    AIGlyph()
                                }
                            }
                            .accessibilityIdentifier("ask-ai-page")
                            Button {
                                editor.focusBody()
                            } label: {
                                IconLabel("app:page.edit", icon: .pencilSimple)
                            }
                            .accessibilityIdentifier("edit-page")
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showsFloatingBar {
                    FloatingActionBar(
                        leading: .init("app:inspector.outline", icon: .listBullets, identifier: "open-inspector") {
                            navigator.toggleInspector(.outline)
                        },
                        prompt: "app:ai.askPage", promptIdentifier: "ask-ai-page",
                        onPrompt: { navigator.isAskingAI = true },
                        trailing: .init("app:page.edit", icon: .pencilSimple, identifier: "edit-page") { editor.focusBody() }
                    )
                    .padding(.bottom, Spacing.s2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.easeOut(), value: keyboardShown)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardShown = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardShown = false
            }
        #endif
    }

    /// The page runs under the toolbar (top), the home indicator (bottom) — and an iPhone Duo's vertical bar, where its
    /// cover fills to the screen's edge while the text keeps clear (the web view's safe area, CSS `env()`).
    private var underBars: Edge.Set {
        #if os(iOS)
            switch verticalBar {
            case .leading?: [.top, .bottom, .leading]
            case .trailing?: [.top, .bottom, .trailing]
            case nil: [.top, .bottom]
            }
        #else
            [.top, .bottom]
        #endif
    }

    /// The floating bar's room over the page's foot (iPhone, keyboard down), above the home indicator.
    private var bottomBarInset: CGFloat {
        #if os(iOS)
            showsFloatingBar ? Size.floatingBar + Spacing.s2 : 0
        #else
            0
        #endif
    }

    #if os(iOS)
        /// iPhone with the keyboard down — and no vertical bar to hold its buttons.
        private var showsFloatingBar: Bool { phoneToolbar && !keyboardShown && verticalBar == nil }
    #endif

    /// Parents of the page, nearest last (root first).
    private var ancestors: [PageSummary] { model.tree.path(to: pageID).dropLast() }

    private func subtitle(_ page: PageSummary) -> Text {
        let edited = Text("app:page.edited \(page.updatedAt, format: .relative(presentation: .named))")
        guard !ancestors.isEmpty else { return edited }
        // The page titles, shown as-is.
        let path = Text(verbatim: ancestors.map(Self.title).joined(separator: " › "))
        return Text("app:common.joined \(path) \(edited)")
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
            #if os(iOS)
                // Touch screens have no cover buttons over the picture (a long press, or this).
                if !page.isLocked {
                    Button {
                        editor.editCover()
                    } label: {
                        IconLabel("app:page.cover", icon: .image)
                    }
                    .accessibilityIdentifier("page-cover")
                }
            #endif
            Divider()
        }
        Button {
            navigator.historyPageID = page.id
        } label: {
            IconLabel("app:history.open", icon: .clockCounterClockwise)
        }
        .accessibilityIdentifier("page-history")
        Menu {
            ForEach(PageExport.Format.allCases) { format in
                Button(format.title) {
                    navigator.exportRequest = ExportRequest(pageID: page.id, format: format)
                }
                .accessibilityIdentifier("export-\(format.rawValue)")
            }
        } label: {
            IconLabel("app:export.menu", icon: .export)
        }
        .accessibilityIdentifier("page-export")
        Divider()
        PageActions(page: page, navigator: navigator)
        Divider()
        #if os(iOS)
            // iPhone: the outline is a sheet, opened from here.
            if !toolbar {
                Button {
                    navigator.toggleInspector(.outline)
                } label: {
                    IconLabel("app:inspector.outline", icon: .listBullets)
                }
                .accessibilityIdentifier("open-inspector")
                Divider()
            }
        #endif
        // The page's facts (once the inspector's Info pane): where it is, when, how big — live while it is open.
        PageFacts(page: page, editor: editor)
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

extension PageExport.Format {
    /// The format's name in the Export menu.
    var title: LocalizedStringKey {
        switch self {
        case .markdown: "app:export.markdown"
        case .html: "app:export.html"
        case .pdf: "app:export.pdf"
        case .json: "app:export.json"
        }
    }
}

/// The page's facts as quiet lines at the end of its ⋯ menu: where it is, when it was made and edited, its size.
private struct PageFacts: View {
    @Environment(AppModel.self) private var model
    let page: PageSummary
    let editor: EditorController?

    var body: some View {
        let path = model.tree.path(to: page.id).dropLast()
            .map { $0.title.isEmpty ? String(localized: "app:page.untitled") : $0.title }
        if !path.isEmpty {
            Text("app:page.location \(path.joined(separator: " › "))")
        }
        Text("app:page.created \(page.createdAt.formatted(date: .abbreviated, time: .shortened))")
        Text("app:page.edited \(page.updatedAt, format: .relative(presentation: .named))")
        if let info = editor?.pageInfo, info.docId == page.id {
            Text("app:page.stats \(info.words.formatted()) \(info.characters.formatted())")
        }
    }
}
