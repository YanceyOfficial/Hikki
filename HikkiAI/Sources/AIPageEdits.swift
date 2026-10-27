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

    /// `"after": "end"` in an insert or a move: after the page's last block.
    public static let endOfPage = "end"

    /// The changes the answer proposes, kept only where they name `blocks` of the page — its block ids in reading
    /// order (rewrite, move and delete one change per block; `after` may be `end`, which reads as the last id; several
    /// inserts may share one `after`: they go in that order); none when there is no block or it can't be read.
    public static func changes(in answer: String, blocks: [String]) -> [ProposedPageChange] {
        let known = Set(blocks)
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
            var after = fields["after"] as? String
            if after == endOfPage, let last = blocks.last { after = last }
            let html = (fields["html"] as? String).map { String($0.prefix(maxHTML)) }
            if let after, !known.contains(after) { continue }
            switch kind {
            case "insert":
                guard let html, !html.isEmpty else { continue }
            default:
                guard let block, known.contains(block), !touched.contains(block) else { continue }
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
    /// characters: later blocks are left out, and `omitted` says how many, so the model knows the page goes on past
    /// what it sees (a long page "ended" where the budget ran out, and "at the end" landed in its middle, ISSUE-218).
    public static func pageJSON(_ blocks: [[String: String]], budget: Int = AIPrompts.maxPageText) -> String {
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        var kept: [String] = []
        var used = 0
        var omitted = 0
        for block in blocks {
            guard let data = try? JSONSerialization.data(withJSONObject: block, options: options),
                let line = String(data: data, encoding: .utf8)
            else { continue }
            if used + line.count > budget || omitted > 0 {
                omitted += 1
                continue
            }
            used += line.count
            kept.append(line)
        }
        let tail = omitted > 0 ? "\n],\"omitted\":\(omitted)}" : "\n]}"
        return "{\"blocks\":[\n" + kept.joined(separator: ",\n") + tail
    }

    static let instructions = """


        The open page is given as JSON blocks (id, type, inline HTML). When the user asks you to change that page — \
        rewrite, fix, add to, reorder or remove parts of it — or to check it (proofread it, find its mistakes, compare \
        it with an answer key, a picture or another source), propose what you would change as changes: say in a \
        sentence or two what you found and will change, then end your reply with one fenced block listing the \
        changes, with nothing after it. The user approves each change in the page, so never only list corrections and \
        wait to be told to apply them; a reply that changes nothing (an explanation, a summary, a check that found \
        nothing wrong) has no changes block:
        ```hikki-changes
        {"changes":[{"kind":"rewrite","block":"<id>","html":"<the block's new inline HTML>","title":"<the gist of the new text, a few words>","why":"<one short reason>"}]}
        ```
        Kinds:
        - rewrite: one block's text is replaced — "block", "html".
        - insert: a new block — "after" (the id it follows: the last id in the list puts it at the end of the page, \
        and "end" means the same; null for the top of the page), "type" (paragraph, heading1, heading2 or heading3; \
        after a list item it becomes the next item), "html". To add several blocks in one place, list several inserts \
        with the same "after", in reading order, one block each: a paragraph break is a new insert, never <br><br> \
        inside one block.
        - move: "block" goes after "after" (an id, "end" for the end of the page, or null for the top).
        - delete: "block" is removed.
        When the page JSON has "omitted", that many more blocks follow the ones shown and were left out for length: \
        they are part of the page, "end" means after them, and say so when asked about what you can't see.
        Rules: use the page's block ids exactly as given; at most one change per existing block; each change touches \
        one block, so prefer several small changes to one large one; in html use only inline tags (strong, em, u, s, \
        code, a with href, br) and keep the formatting the text already has; keep the page's language unless asked to \
        translate; write titles and reasons in the user's language. A title says what the block will say (its gist \
        in a few words, or the correction itself: "He know → He knows"), never the kind of change — the card shows \
        the kind itself, so "Insert" or "Rewrite" as a title says nothing. Never put a hikki-changes block in a reply \
        that doesn't change the page.
        """
}
