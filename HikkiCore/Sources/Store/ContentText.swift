import Foundation

/// Text pulled out of a stored Tiptap document for the pieces of the app that need it (search, Spotlight, the split
/// view's PDF list). The document is otherwise opaque to Swift. A block's text reads as the editor's
/// (`editor/src/core/extract.ts`): a page mention as "@title", an inline formula as its LaTeX, a hard break as a
/// line break — `design/fixtures/content-text.json` holds both sides to the same answers.
public enum ContentText {
    /// A line of text the editor can scroll to: a paragraph, heading, code block or toggle summary with its block id.
    public struct Block: Sendable, Equatable {
        /// The editor's block id; "" for a block stored without one (it can be found, not landed on).
        public var id: String
        public var isHeading: Bool
        public var text: String

        public init(id: String, isHeading: Bool, text: String) {
            self.id = id
            self.isHeading = isHeading
            self.text = text
        }
    }

    /// Everything search and Spotlight read of a document, from one pass over it.
    public struct Extract: Sendable, Equatable {
        /// Every heading's text on one line (whitespace runs as one space), in document order; empty ones skipped.
        public var headings: [String] = []
        /// Every text block with some text, in document order, nested ones (lists, tables, toggles, callouts,
        /// columns) included.
        public var blocks: [Block] = []
        /// The files the document attaches (inline images and file attachments stored as assets), each once.
        public var assets: [AssetReference] = []

        public init(headings: [String] = [], blocks: [Block] = [], assets: [AssetReference] = []) {
            self.headings = headings
            self.blocks = blocks
            self.assets = assets
        }
    }

    public static func extract(_ content: JSONValue?) -> Extract {
        var out = Extract()
        guard let content else { return out }
        var seenAssets = Set<String>()
        visit(content, into: &out, seenAssets: &seenAssets)
        return out
    }

    /// The text of every heading, in document order, nested ones (in toggles, callouts, columns) included;
    /// empty headings are skipped.
    public static func headings(in content: JSONValue?) -> [String] { extract(content).headings }

    /// Every text block with some text, in document order — what search finds a match in and lands on.
    public static func blocks(in content: JSONValue?) -> [Block] { extract(content).blocks }

    /// The files a document attaches, in order, each once.
    public static func assets(in content: JSONValue?) -> [AssetReference] { extract(content).assets }

    private static let textBlockTypes: Set<String> = ["paragraph", "heading", "codeBlock", "detailsSummary"]

    private static func visit(_ node: JSONValue, into out: inout Extract, seenAssets: inout Set<String>) {
        guard case .object(let fields) = node else { return }
        let type: String? = if case .string(let type)? = fields["type"] { type } else { nil }
        let attrs: [String: JSONValue] = if case .object(let attrs)? = fields["attrs"] { attrs } else { [:] }
        let id: String? = if case .string(let id)? = attrs["id"], !id.isEmpty { id } else { nil }
        if let type, textBlockTypes.contains(type) {
            let text = plainText(of: node, hardBreak: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let isHeading = type == "heading"
            if isHeading { out.headings.append(text.split(whereSeparator: \.isWhitespace).joined(separator: " ")) }
            out.blocks.append(Block(id: id ?? "", isHeading: isHeading, text: text))
            return
        }
        if type == "image" || type == "fileAttachment", case .string(let src)? = attrs["src"],
            let name = AssetStore.name(fromURL: src), seenAssets.insert(name).inserted
        {
            var label: String?
            if type == "fileAttachment", case .string(let fileName)? = attrs["name"], !fileName.isEmpty { label = fileName }
            out.assets.append(AssetReference(name: name, label: label, blockId: id))
        }
        if case .array(let children)? = fields["content"] {
            for child in children { visit(child, into: &out, seenAssets: &seenAssets) }
        }
    }

    /// The text of a node and everything in it: a page mention as "@title", an inline formula as its LaTeX, a hard
    /// break as `hardBreak` (a space by default; a block's text keeps it as a line break, as the editor does).
    static func plainText(of node: JSONValue, hardBreak: String = " ") -> String {
        guard case .object(let fields) = node else { return "" }
        if case .string(let text)? = fields["text"] { return text }
        switch fields["type"] {
        case .string("hardBreak"): return hardBreak
        case .string("mention"):
            if case .object(let attrs)? = fields["attrs"], case .string(let label)? = attrs["label"] { return "@\(label)" }
            return "@"
        case .string("inlineMath"):
            if case .object(let attrs)? = fields["attrs"], case .string(let latex)? = attrs["latex"] { return latex }
            return ""
        default: break
        }
        guard case .array(let children)? = fields["content"] else { return "" }
        return children.map { plainText(of: $0, hardBreak: hardBreak) }.joined()
    }
}

/// A file a document attaches: the asset's name, the file's own name when it was attached as a file, and the block
/// that shows it (search opens a file's match there).
public struct AssetReference: Sendable, Equatable {
    public var name: String
    public var label: String?
    public var blockId: String?

    public init(name: String, label: String? = nil, blockId: String? = nil) {
        self.name = name
        self.label = label
        self.blockId = blockId
    }
}

extension DocumentRecord {
    /// Headings, text blocks and attached files of the page, from its stored content in one pass.
    public var contentText: ContentText.Extract { ContentText.extract(try? contentValue()) }

    /// The page's headings, from its stored content.
    public var headings: [String] { contentText.headings }

    /// The page's text blocks with their ids, from its stored content (search lands on them).
    public var textBlocks: [ContentText.Block] { contentText.blocks }

    /// The files the page attaches, from its stored content.
    public var assetReferences: [AssetReference] { contentText.assets }
}
