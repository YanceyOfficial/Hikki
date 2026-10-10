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
        case .bold: String(localized: "app:format.bold")
        case .italic: String(localized: "app:format.italic")
        case .strike: String(localized: "app:format.strikethrough")
        case .code: String(localized: "app:format.inlineCode")
        case .heading1: String(localized: "app:format.heading1")
        case .heading2: String(localized: "app:format.heading2")
        case .heading3: String(localized: "app:format.heading3")
        case .paragraph: String(localized: "app:format.text")
        case .bulletList: String(localized: "app:format.bulletedList")
        case .orderedList: String(localized: "app:format.numberedList")
        case .taskList: String(localized: "app:format.todoList")
        case .blockquote: String(localized: "app:format.quote")
        case .codeBlock: String(localized: "app:format.codeBlock")
        case .undo: String(localized: "app:format.undo")
        case .redo: String(localized: "app:format.redo")
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
