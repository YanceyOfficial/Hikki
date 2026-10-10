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
                .disabled(navigator == nil)
        }
        CommandGroup(after: .newItem) {
            Button("Search…") { navigator?.isSearching = true }
                .keyboardShortcut("k")
                .disabled(navigator == nil)
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
}
