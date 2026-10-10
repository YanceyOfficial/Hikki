import SwiftUI

/// Menu bar (macOS, iPadOS). Formatting items have no key equivalents: ProseMirror already owns
/// ⌘B/⌘I/⌘Z inside the editor, and binding them here too would toggle twice.
struct AppCommands: Commands {
    @FocusedValue(\.editor) private var editor
    @FocusedValue(\.navigator) private var navigator

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("app:page.new") { navigator?.newPage() }
                .keyboardShortcut("n")
            Button("app:tabs.new") { navigator?.openInNewTab(.home) }
                .keyboardShortcut("t")
            Button("app:tabs.close") {
                guard let navigator else { return }
                if !navigator.closeTab(navigator.tabs.activeID) { closeWindow() }
            }
            .keyboardShortcut("w")
            Divider()
            Button("app:menu.search") { navigator?.isSearching = true }
                .keyboardShortcut("k")
        }
        CommandMenu("app:menu.go") {
            Button("app:chrome.back") { navigator?.goBack() }
                .keyboardShortcut("[")
                .disabled(navigator?.tabs.active.canGoBack != true)
            Button("app:chrome.forward") { navigator?.goForward() }
                .keyboardShortcut("]")
                .disabled(navigator?.tabs.active.canGoForward != true)
            Divider()
            Button("app:tabs.next") { navigator?.selectNeighborTab(1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("app:tabs.previous") { navigator?.selectNeighborTab(-1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
            Button("app:nav.home") { navigator?.go(.home) }
            Button("app:nav.trash") { navigator?.go(.trash) }
        }
        CommandMenu("app:menu.format") {
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
