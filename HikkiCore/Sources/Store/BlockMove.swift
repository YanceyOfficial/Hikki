import Foundation

/// Blocks moved from one page to the end of another (the block menu's Move to): the target's body, text and word
/// count afterwards. The blocks come from the editor as the target takes them (a list item already in its list).
public enum BlockMove {
    /// `content` with `blocks` at its end; a page holding only an empty line (a new page) takes them in its place.
    public static func appending(_ blocks: [JSONValue], to content: JSONValue?) -> JSONValue {
        var fields: [String: JSONValue] = if case .object(let fields)? = content { fields } else { ["type": .string("doc")] }
        var children: [JSONValue] = if case .array(let children)? = fields["content"] { children } else { [] }
        if children.count == 1, isEmptyLine(children[0]) { children = [] }
        fields["content"] = .array(children + blocks)
        return .object(fields)
    }

    /// The page's text with the moved blocks' after it, a line apart (`plainText` in the editor joins blocks so).
    public static func text(_ pageText: String, adding moved: String) -> String {
        [pageText, moved].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func isEmptyLine(_ node: JSONValue) -> Bool {
        guard case .object(let fields) = node, case .string("paragraph")? = fields["type"] else { return false }
        if case .array(let children)? = fields["content"] { return children.isEmpty }
        return true
    }
}

/// What the editor asks for when it moves blocks (`moveBlocks`): from page `source` to the end of page `target`.
public struct BlockMoveRequest: Sendable, Equatable {
    public var source: String
    public var target: String
    public var blocks: [JSONValue]
    public var text: String
    public var words: Int

    public init(source: String, target: String, blocks: [JSONValue], text: String, words: Int) {
        self.source = source
        self.target = target
        self.blocks = blocks
        self.text = text
        self.words = words
    }
}
