import HikkiCore
import HikkiUI
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    // One editor (and one WKWebView) per window, reused across pages.
    @State private var editor = EditorController()
    @State private var navigator = Navigator()

    var body: some View {
        @Bindable var navigator = navigator
        NavigationSplitView {
            SidebarView(navigator: navigator)
                .navigationSplitViewColumnWidth(
                    min: Theme.Metrics.sidebarMinWidth, ideal: Theme.Metrics.sidebarIdealWidth, max: Theme.Metrics.sidebarMaxWidth
                )
        } detail: {
            switch navigator.route {
            case .page(let id):
                PageScreen(pageID: id, editor: editor, navigator: navigator)
            case .trash:
                TrashView()
            case .home, nil:
                HomeView(navigator: navigator)
            }
        }
        .sheet(isPresented: $navigator.isSearching) {
            SearchPalette(navigator: navigator)
        }
        .task { await model.observe() }
        .onAppear {
            navigator.attach(model)
            editor.attach(store: model.store, assets: model.assets)
        }
        .onChange(of: navigator.route) { _, route in editor.open(documentID: route?.pageID) }
        .onChange(of: model.tree) { _, tree in
            // The open page was trashed (here or in another window).
            if let id = navigator.route?.pageID, tree.page(id) == nil { navigator.route = .home }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await editor.flush(reason: "scenePhase-\(phase)") } }
        }
        .focusedSceneValue(\.editor, editor)
        .focusedSceneValue(\.navigator, navigator)
        .tint(Theme.accent)
    }
}
