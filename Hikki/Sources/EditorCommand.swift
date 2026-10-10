import HikkiUI

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

    var icon: Icon {
        switch self {
        case .bold: .textB
        case .italic: .textItalic
        case .strike: .textStrikethrough
        case .code: .code
        case .heading1: .textHOne
        case .heading2: .textHTwo
        case .heading3: .textHThree
        case .paragraph: .textT
        case .bulletList: .listBullets
        case .orderedList: .listNumbers
        case .taskList: .listChecks
        case .blockquote: .quotes
        case .codeBlock: .codeBlock
        case .undo: .arrowUUpLeft
        case .redo: .arrowUUpRight
        }
    }

    static let menuGroups: [[EditorCommand]] = [
        [.bold, .italic, .strike, .code],
        [.paragraph, .heading1, .heading2, .heading3],
        [.bulletList, .orderedList, .taskList, .blockquote, .codeBlock],
    ]
}
