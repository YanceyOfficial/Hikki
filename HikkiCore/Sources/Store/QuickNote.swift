import Foundation

/// A page made in one tap from Home: a title and plain lines (today's note, what the clipboard holds), as the page's
/// content in the editor's schema — one paragraph per line.
public struct QuickNote: Equatable, Sendable {
    public var title: String
    public var lines: [String]

    public init(title: String, lines: [String]) {
        self.title = title
        self.lines = lines
    }

    /// Longest title taken from the clipboard's first line.
    static let titleLimit = 80

    /// What the clipboard holds as a page: its first line is the title (a link alone: its host, the link the body),
    /// the rest the body; nil when it holds nothing but blanks.
    public static func fromClipboard(_ text: String) -> QuickNote? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = lines.firstIndex(where: { !$0.isEmpty }) else { return nil }
        let head = lines[first]
        var body = Array(lines[(first + 1)...])
        while body.last?.isEmpty == true { body.removeLast() }
        if body.isEmpty, let url = URL(string: head), let scheme = url.scheme, ["http", "https"].contains(scheme),
            let host = url.host()
        {
            let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return QuickNote(title: name, lines: [head])
        }
        if head.count > titleLimit {
            // A long first line is text, not a title: all of it goes in the body, its start names the page.
            return QuickNote(title: String(head.prefix(titleLimit)).trimmingCharacters(in: .whitespaces) + "…", lines: [head] + body)
        }
        return QuickNote(title: head, lines: body)
    }

    /// The body as the editor's JSON: a paragraph per line (an empty line an empty paragraph).
    public var content: JSONValue {
        let paragraphs: [JSONValue] = lines.map { line in
            line.isEmpty
                ? .object(["type": .string("paragraph")])
                : .object([
                    "type": .string("paragraph"),
                    "content": .array([.object(["type": .string("text"), "text": .string(line)])]),
                ])
        }
        return .object([
            "type": .string("doc"), "content": .array(paragraphs.isEmpty ? [.object(["type": .string("paragraph")])] : paragraphs),
        ])
    }

    /// The body's plain text (search; the editor recounts words when the page is edited).
    public var text: String { lines.joined(separator: "\n") }

    /// Title and body in words, counted as the editor counts them (`WordCount`).
    public var wordCount: Int { WordCount.count(title: title, text: text) }
}
