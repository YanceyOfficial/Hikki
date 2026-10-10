import SwiftUI

extension FocusedValues {
    @Entry var editor: EditorController?
}

/// Menu bar (macOS, iPadOS) entries. No key equivalents: ProseMirror already owns ⌘B/⌘I/⌘Z inside the
/// editor, and binding them here too would toggle twice.
struct FormatCommands: Commands {
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
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
