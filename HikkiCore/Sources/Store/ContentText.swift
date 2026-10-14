import Foundation

/// Text pulled out of a stored Tiptap document for the pieces of the app that need it (the search index weighs
/// headings above body text). The document is otherwise opaque to Swift.
public enum ContentText {
    /// The text of every heading, in document order, nested ones (in toggles, callouts, columns) included;
    /// empty headings are skipped.
    public static func headings(in content: JSONValue?) -> [String] {
        guard let content else { return [] }
        var out: [String] = []
        collectHeadings(content, into: &out)
        return out
    }

    private static func collectHeadings(_ node: JSONValue, into out: inout [String]) {
        guard case .object(let fields) = node else { return }
        if case .string("heading")? = fields["type"] {
            let text = plainText(of: node).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { out.append(text) }
            return
        }
        if case .array(let children)? = fields["content"] {
            for child in children { collectHeadings(child, into: &out) }
        }
    }

    /// The text of a node and everything in it (a hard break counts as a space).
    static func plainText(of node: JSONValue) -> String {
        guard case .object(let fields) = node else { return "" }
        if case .string(let text)? = fields["text"] { return text }
        if case .string("hardBreak")? = fields["type"] { return " " }
        guard case .array(let children)? = fields["content"] else { return "" }
        return children.map(plainText).joined()
    }
}

extension DocumentRecord {
    /// The page's headings, from its stored content.
    public var headings: [String] { ContentText.headings(in: try? contentValue()) }
}
