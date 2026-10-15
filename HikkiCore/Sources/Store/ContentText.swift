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

    /// A line of text the editor can scroll to: a paragraph, heading, code block or toggle summary with its block id.
    public struct Block: Sendable, Equatable {
        public var id: String
        public var isHeading: Bool
        public var text: String

        public init(id: String, isHeading: Bool, text: String) {
            self.id = id
            self.isHeading = isHeading
            self.text = text
        }
    }

    /// Every text block with an id and some text, in document order, nested ones (lists, tables, toggles, callouts,
    /// columns) included — what search finds a match in and lands on.
    public static func blocks(in content: JSONValue?) -> [Block] {
        guard let content else { return [] }
        var out: [Block] = []
        collectBlocks(content, into: &out)
        return out
    }

    private static let textBlockTypes: Set<String> = ["paragraph", "heading", "codeBlock", "detailsSummary"]

    private static func collectBlocks(_ node: JSONValue, into out: inout [Block]) {
        guard case .object(let fields) = node, case .string(let type)? = fields["type"] else { return }
        if textBlockTypes.contains(type) {
            if case .object(let attrs)? = fields["attrs"], case .string(let id)? = attrs["id"], !id.isEmpty {
                let text = plainText(of: node).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { out.append(Block(id: id, isHeading: type == "heading", text: text)) }
            }
            return
        }
        if case .array(let children)? = fields["content"] {
            for child in children { collectBlocks(child, into: &out) }
        }
    }

    /// The files a document attaches (inline images and file attachments stored as assets), in order, each once.
    public static func assets(in content: JSONValue?) -> [AssetReference] {
        guard let content else { return [] }
        var out: [AssetReference] = []
        var seen = Set<String>()
        collectAssets(content, into: &out, seen: &seen)
        return out
    }

    private static func collectAssets(_ node: JSONValue, into out: inout [AssetReference], seen: inout Set<String>) {
        guard case .object(let fields) = node else { return }
        if case .string(let type)? = fields["type"], type == "image" || type == "fileAttachment",
            case .object(let attrs)? = fields["attrs"], case .string(let src)? = attrs["src"],
            let name = AssetStore.name(fromURL: src), seen.insert(name).inserted
        {
            var label: String?
            if type == "fileAttachment", case .string(let fileName)? = attrs["name"], !fileName.isEmpty { label = fileName }
            out.append(AssetReference(name: name, label: label))
        }
        if case .array(let children)? = fields["content"] {
            for child in children { collectAssets(child, into: &out, seen: &seen) }
        }
    }

    /// The text of a node and everything in it (a hard break counts as a space, a page mention as "@title").
    static func plainText(of node: JSONValue) -> String {
        guard case .object(let fields) = node else { return "" }
        if case .string(let text)? = fields["text"] { return text }
        if case .string("hardBreak")? = fields["type"] { return " " }
        // A page mention ("@" in the editor) reads as its label.
        if case .string("mention")? = fields["type"] {
            if case .object(let attrs)? = fields["attrs"], case .string(let label)? = attrs["label"] { return "@\(label)" }
            return ""
        }
        guard case .array(let children)? = fields["content"] else { return "" }
        return children.map(plainText).joined()
    }
}

/// A file a document attaches: the asset's name, and the file's own name when it was attached as a file.
public struct AssetReference: Sendable, Equatable {
    public var name: String
    public var label: String?

    public init(name: String, label: String? = nil) {
        self.name = name
        self.label = label
    }
}

extension DocumentRecord {
    /// The page's headings, from its stored content.
    public var headings: [String] { ContentText.headings(in: try? contentValue()) }

    /// The page's text blocks with their ids, from its stored content (search lands on them).
    public var textBlocks: [ContentText.Block] { ContentText.blocks(in: try? contentValue()) }

    /// The files the page attaches, from its stored content.
    public var assetReferences: [AssetReference] { ContentText.assets(in: try? contentValue()) }
}
