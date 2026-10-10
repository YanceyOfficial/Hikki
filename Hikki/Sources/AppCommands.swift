import SwiftUI

/// Menu bar (macOS, iPadOS). Formatting items have no key equivalents: ProseMirror already owns
/// ⌘B/⌘I/⌘Z inside the editor, and binding them here too would toggle twice.
struct AppCommands: Commands {
    @FocusedValue(\.editor) private var editor
    @FocusedValue(\.navigator) private var navigator

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Page") { navigator?.newPage() }
                .keyboardShortcut("n")
            Button("New Tab") { navigator?.openInNewTab(.home) }
                .keyboardShortcut("t")
            Button("Close Tab") {
                guard let navigator else { return }
                if !navigator.closeTab(navigator.tabs.activeID) { closeWindow() }
            }
            .keyboardShortcut("w")
            Divider()
            Button("Search…") { navigator?.isSearching = true }
                .keyboardShortcut("k")
        }
        CommandMenu("Go") {
            Button("Back") { navigator?.goBack() }
                .keyboardShortcut("[")
                .disabled(navigator?.tabs.active.canGoBack != true)
            Button("Forward") { navigator?.goForward() }
                .keyboardShortcut("]")
                .disabled(navigator?.tabs.active.canGoForward != true)
            Divider()
            Button("Next Tab") { navigator?.selectNeighborTab(1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Previous Tab") { navigator?.selectNeighborTab(-1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
            Button("Home") { navigator?.go(.home) }
            Button("Trash") { navigator?.go(.trash) }
        }
        CommandMenu("Format") {
            ForEach(EditorCommand.menuGroups, id: \.self) { group in
                ForEach(group) { command in
                    Button(command.title) { editor?.exec(command) }
                }
                Divider()
            }
        }
    }

    private func closeWindow() {
        #if os(macOS)
            NSApp.keyWindow?.performClose(nil)
        #endif
    }
}
