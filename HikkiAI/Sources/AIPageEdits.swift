import Foundation

/// A change to the open page an Ask AI answer proposes (see `AIPageEdits`), checked against the page's blocks.
public struct ProposedPageChange: Equatable, Sendable {
    /// rewrite, insert, move or delete.
    public var kind: String
    public var block: String?
    public var after: String?
    public var html: String?
    /// For an insert: paragraph, heading1, heading2 or heading3.
    public var type: String?
    public var title: String
    public var why: String?

    public init(
        kind: String, block: String? = nil, after: String? = nil, html: String? = nil, type: String? = nil, title: String,
        why: String? = nil
    ) {
        self.kind = kind
        self.block = block
        self.after = after
        self.html = html
        self.type = type
        self.title = title
        self.why = why
    }
}

/// Ask AI editing the open page: the page goes to the model as blocks with their ids, and an answer that changes it
/// ends with a fenced `hikki-changes` block of JSON — one change per block, reviewed card by card in the page. The
/// fence never shows in the chat; what's in it is untrusted and checked here (known kinds and block ids only).
public enum AIPageEdits {
    static let fence = "```hikki-changes"
    static let maxChanges = 40
    static let maxHTML = 4000
    static let maxTitle = 120
    static let maxWhy = 300
    static let kinds: Set<String> = ["rewrite", "insert", "move", "delete"]
    static let insertTypes: Set<String> = ["paragraph", "heading1", "heading2", "heading3"]

    /// The answer as the chat shows it: without its changes block (or pictures block) — and, while it streams, without a fence line
    /// still being typed that may turn out to be that block.
    public static func prose(_ answer: String) -> String {
        // The first of the answer's hidden blocks (changes, pictures) ends what the chat shows.
        let hidden = [fence, AIPictures.fence].compactMap { answer.range(of: $0)?.lowerBound }.min()
        if let start = hidden {
            return String(answer[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lastLine = answer.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        if lastLine.count > 3, fence.hasPrefix(lastLine) || AIPictures.fence.hasPrefix(lastLine) {
            return String(answer.dropLast(lastLine.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return answer
    }

    /// Whether the answer has started its changes block (the chat says it is preparing changes meanwhile).
    public static func hasChanges(_ answer: String) -> Bool { answer.contains(fence) }

    /// The changes the answer proposes, kept only where they name `blocks` of the page (rewrite, move and delete one
    /// change per block); none when there is no block or it can't be read.
    public static func changes(in answer: String, blocks: Set<String>) -> [ProposedPageChange] {
        guard let start = answer.range(of: fence) else { return [] }
        var body = answer[start.upperBound...]
        if let end = body.range(of: "```") { body = body[..<end.lowerBound] }
        guard let open = body.firstIndex(of: "{"), let close = body.lastIndex(of: "}"), open < close,
            let data = String(body[open...close]).data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = object["changes"] as? [Any]
        else { return [] }
        var touched: Set<String> = []
        var out: [ProposedPageChange] = []
        for item in list {
            guard out.count < maxChanges, let fields = item as? [String: Any],
                let kind = fields["kind"] as? String, kinds.contains(kind)
            else { continue }
            let block = fields["block"] as? String
            let after = fields["after"] as? String
            let html = (fields["html"] as? String).map { String($0.prefix(maxHTML)) }
            if let after, !blocks.contains(after) { continue }
            switch kind {
            case "insert":
                guard let html, !html.isEmpty else { continue }
            default:
                guard let block, blocks.contains(block), !touched.contains(block) else { continue }
                if kind == "rewrite", html == nil { continue }
                if kind == "move", after == block { continue }
                touched.insert(block)
            }
            let type = (fields["type"] as? String).flatMap { insertTypes.contains($0) ? $0 : nil }
            out.append(
                ProposedPageChange(
                    kind: kind, block: kind == "insert" ? nil : block, after: kind == "insert" || kind == "move" ? after : nil,
                    html: kind == "rewrite" || kind == "insert" ? html : nil,
                    type: kind == "insert" ? (type ?? "paragraph") : nil,
                    title: String(((fields["title"] as? String) ?? "").prefix(maxTitle)),
                    why: (fields["why"] as? String).map { String($0.prefix(maxWhy)) }.flatMap { $0.isEmpty ? nil : $0 }))
        }
        return out
    }

    /// The open page's blocks (`id`, `type`, `html` each, in order) as the JSON the model gets, up to `budget`
    /// characters (later blocks left out).
    public static func pageJSON(_ blocks: [[String: String]], budget: Int = AIPrompts.maxPageText) -> String {
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        var kept: [String] = []
        var used = 0
        for block in blocks {
            guard let data = try? JSONSerialization.data(withJSONObject: block, options: options),
                let line = String(data: data, encoding: .utf8)
            else { continue }
            if used + line.count > budget { break }
            used += line.count
            kept.append(line)
        }
        return "{\"blocks\":[\n" + kept.joined(separator: ",\n") + "\n]}"
    }

    static let instructions = """


        The open page is given as JSON blocks (id, type, inline HTML). When the user asks you to change that page — \
        rewrite, fix, add to, reorder or remove parts of it — and only then, say in a sentence or two what you will \
        change, then end your reply with one fenced block listing the changes, with nothing after it:
        ```hikki-changes
        {"changes":[{"kind":"rewrite","block":"<id>","html":"<the block's new inline HTML>","title":"<what changes, a few words>","why":"<one short reason>"}]}
        ```
        Kinds:
        - rewrite: one block's text is replaced — "block", "html".
        - insert: a new block — "after" (the id it follows, or null for the top of the page), "type" (paragraph, \
        heading1, heading2 or heading3; after a list item it becomes the next item), "html".
        - move: "block" goes after "after" (an id, or null for the top).
        - delete: "block" is removed.
        Rules: use the page's block ids exactly as given; at most one change per block; each change touches one block, \
        so prefer several small changes to one large one; in html use only inline tags (strong, em, u, s, code, a with \
        href, br) and keep the formatting the text already has; keep the page's language unless asked to translate; \
        write titles and reasons in the user's language. Never put a hikki-changes block in a reply that doesn't change \
        the page.
        """
}
