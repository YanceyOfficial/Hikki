import HikkiCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    // One editor (and one WKWebView) per window, reused across documents.
    @State private var editor = EditorController()
    @State private var selection: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            if selection != nil {
                EditorView(controller: editor)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .navigationTitle("")
            } else {
                ContentUnavailableView("No Page Selected", systemImage: "doc.text", description: Text("Create or pick a page."))
            }
        }
        .task { await model.observeSummaries() }
        .onAppear { editor.attach(store: model.store) }
        .onChange(of: selection) { _, id in editor.open(documentID: id) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await editor.flush(reason: "scenePhase-\(phase)") } }
        }
        .focusedSceneValue(\.editor, editor)
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(model.summaries) { doc in
                Text(doc.title.isEmpty ? "Untitled" : doc.title)
                    .lineLimit(1)
                    .tag(doc.id)
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(doc.id) }
                    }
            }
            .onDelete { offsets in offsets.map { model.summaries[$0].id }.forEach(delete) }
        }
        .navigationTitle("Hikki")
        .toolbar {
            ToolbarItem {
                Button("New Page", systemImage: "square.and.pencil") {
                    if let id = model.createDocument() { selection = id }
                }
                .keyboardShortcut("n")
            }
            ToolbarItem {
                Menu("More", systemImage: "ellipsis.circle") {
                    ShareLink("Export Logs", items: model.exportableFiles)
                }
            }
        }
    }

    private func delete(_ id: String) {
        if selection == id { selection = nil }
        model.deleteDocument(id: id)
    }
}
