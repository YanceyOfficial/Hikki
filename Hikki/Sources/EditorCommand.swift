/// Mirrors COMMANDS in editor/src/protocol.ts.
enum EditorCommand: String, CaseIterable, Identifiable, Hashable {
    case bold, italic, strike, code
    case heading1, heading2, heading3, paragraph
    case bulletList, orderedList, taskList, blockquote, codeBlock
    case undo, redo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strike: "Strikethrough"
        case .code: "Inline Code"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .paragraph: "Text"
        case .bulletList: "Bulleted List"
        case .orderedList: "Numbered List"
        case .taskList: "To-do List"
        case .blockquote: "Quote"
        case .codeBlock: "Code Block"
        case .undo: "Undo"
        case .redo: "Redo"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strike: "strikethrough"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .heading3: "textformat.size.smaller"
        case .paragraph: "textformat"
        case .bulletList: "list.bullet"
        case .orderedList: "list.number"
        case .taskList: "checklist"
        case .blockquote: "text.quote"
        case .codeBlock: "curlybraces"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        }
    }

    static let menuGroups: [[EditorCommand]] = [
        [.bold, .italic, .strike, .code],
        [.paragraph, .heading1, .heading2, .heading3],
        [.bulletList, .orderedList, .taskList, .blockquote, .codeBlock],
    ]
}
