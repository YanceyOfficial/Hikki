import Foundation

/// A stored Tiptap document flattened to the blocks a reader sees — one per paragraph, heading, list item, code
/// block, table row, picture… — as text. What the page history previews and compares (it never renders the editor).
public struct TextBlock: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case paragraph, heading1, heading2, heading3, bullet, numbered, task, taskDone, quote, code, math, table, media, rule
    }

    public var kind: Kind
    public var text: String
    /// Nesting below the page (list levels, toggles, callouts, columns).
    public var depth: Int

    public init(kind: Kind, text: String, depth: Int = 0) {
        self.kind = kind
        self.text = text
        self.depth = depth
    }

    /// The blocks of a stored document, in reading order.
    public static func blocks(in content: JSONValue?) -> [TextBlock] {
        guard let content else { return [] }
        var out: [TextBlock] = []
        collect(content, depth: 0, quote: false, into: &out)
        return out
    }

    private static func collect(_ node: JSONValue, depth: Int, quote: Bool, listKind: Kind? = nil, into out: inout [TextBlock]) {
        guard case .object(let fields) = node, case .string(let type)? = fields["type"] else { return }
        let attrs: [String: JSONValue] = if case .object(let a)? = fields["attrs"] { a } else { [:] }
        let children: [JSONValue] = if case .array(let c)? = fields["content"] { c } else { [] }
        func text() -> String { ContentText.plainText(of: node) }
        func attr(_ key: String) -> String? {
            if case .string(let value)? = attrs[key], !value.isEmpty { return value }
            return nil
        }
        switch type {
        case "paragraph", "detailsSummary":
            out.append(TextBlock(kind: listKind ?? (quote ? .quote : .paragraph), text: text(), depth: depth))
        case "heading":
            let level = if case .number(let n)? = attrs["level"] { Int(n) } else { 1 }
            out.append(TextBlock(kind: level <= 1 ? .heading1 : level == 2 ? .heading2 : .heading3, text: text(), depth: depth))
        case "codeBlock":
            out.append(TextBlock(kind: .code, text: text(), depth: depth))
        case "blockMath", "inlineMath":
            out.append(TextBlock(kind: .math, text: attr("latex") ?? "", depth: depth))
        case "horizontalRule":
            out.append(TextBlock(kind: .rule, text: "", depth: depth))
        case "image", "video", "audio", "fileAttachment", "embed":
            out.append(TextBlock(kind: .media, text: attr("name") ?? attr("alt") ?? attr("title") ?? attr("src") ?? type, depth: depth))
        case "tableRow":
            let cells = children.map { ContentText.plainText(of: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            out.append(TextBlock(kind: .table, text: cells.joined(separator: " | "), depth: depth))
        case "bulletList", "orderedList", "taskList":
            let kind: Kind = type == "bulletList" ? .bullet : type == "orderedList" ? .numbered : .task
            for child in children { collect(child, depth: depth, quote: quote, listKind: kind, into: &out) }
        case "listItem", "taskItem":
            var kind = listKind ?? .bullet
            if type == "taskItem", case .bool(true)? = attrs["checked"] { kind = .taskDone }
            // The item's own line(s) take the marker; a nested list goes one level in.
            for child in children {
                if case .object(let f) = child, case .string(let t)? = f["type"], t.hasSuffix("List") {
                    collect(child, depth: depth + 1, quote: quote, into: &out)
                } else {
                    collect(child, depth: depth, quote: quote, listKind: kind, into: &out)
                }
            }
        case "blockquote":
            for child in children { collect(child, depth: depth, quote: true, into: &out) }
        case "doc", "table", "columns", "column", "detailsContent":
            for child in children { collect(child, depth: depth, quote: quote, into: &out) }
        default:
            // Containers (toggles, callouts, anything newer): their blocks one level in.
            if children.isEmpty {
                let value = text()
                if !value.isEmpty { out.append(TextBlock(kind: .paragraph, text: value, depth: depth)) }
            } else {
                for child in children {
                    collect(child, depth: depth + (type == "details" || type == "callout" ? 1 : 0), quote: quote, into: &out)
                }
            }
        }
    }
}

/// How a block or a run of text compares between two versions.
public enum DiffChange: String, Sendable, Equatable {
    case same, added, removed
}

/// A stretch of a changed block's text.
public struct DiffRun: Sendable, Equatable {
    public var text: String
    public var change: DiffChange

    public init(_ text: String, _ change: DiffChange) {
        self.text = text
        self.change = change
    }
}

/// One block of a comparison: unchanged, added, removed, or edited (then `runs` mark what changed inside it).
public struct BlockDiff: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case same, added, removed, changed
    }

    public var block: TextBlock
    public var status: Status
    /// The block's text in pieces; a single run unless the block was edited.
    public var runs: [DiffRun]
}

/// Compares two versions of a page block by block, and an edited block word by word (CJK character by character),
/// the way a reader would describe the change.
public enum PageDiff {
    /// The blocks of `new`, with the blocks of `old` it no longer has put back where they were, marked.
    public static func compare(old: [TextBlock], new: [TextBlock]) -> [BlockDiff] {
        let difference = new.difference(from: old)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var result: [BlockDiff] = []
        var i = 0
        var j = 0
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, !removed.contains(i), !inserted.contains(j) {
                result.append(BlockDiff(block: new[j], status: .same, runs: [DiffRun(new[j].text, .same)]))
                i += 1
                j += 1
                continue
            }
            var gone: [TextBlock] = []
            var came: [TextBlock] = []
            while i < old.count, removed.contains(i) {
                gone.append(old[i])
                i += 1
            }
            while j < new.count, inserted.contains(j) {
                came.append(new[j])
                j += 1
            }
            if gone.isEmpty && came.isEmpty {
                // Can't happen with a consistent difference; never loop forever on one that isn't.
                if i < old.count {
                    gone.append(old[i])
                    i += 1
                }
                if j < new.count {
                    came.append(new[j])
                    j += 1
                }
            }
            result += pair(gone, came)
        }
        return result
    }

    /// A run of removed blocks and the run of added blocks in their place: those of the same kind whose words
    /// overlap enough are one edited block; the rest stay removed / added.
    private static func pair(_ gone: [TextBlock], _ came: [TextBlock]) -> [BlockDiff] {
        var out: [BlockDiff] = []
        var g = 0
        var c = 0
        while g < gone.count || c < came.count {
            if g < gone.count, c < came.count, gone[g].kind == came[c].kind, similar(gone[g].text, came[c].text) {
                out.append(BlockDiff(block: came[c], status: .changed, runs: words(old: gone[g].text, new: came[c].text)))
                g += 1
                c += 1
            } else if g < gone.count, c >= came.count || gone.count - g >= came.count - c {
                out.append(BlockDiff(block: gone[g], status: .removed, runs: [DiffRun(gone[g].text, .removed)]))
                g += 1
            } else {
                out.append(BlockDiff(block: came[c], status: .added, runs: [DiffRun(came[c].text, .added)]))
                c += 1
            }
        }
        return out
    }

    /// At least a third of the longer text's words are shared.
    static func similar(_ a: String, _ b: String) -> Bool {
        let x = tokens(a).filter { !$0.allSatisfy(\.isWhitespace) }
        let y = tokens(b).filter { !$0.allSatisfy(\.isWhitespace) }
        guard !x.isEmpty || !y.isEmpty else { return true }
        let shared = y.count - y.difference(from: x).insertions.count
        return Double(shared) >= Double(max(x.count, y.count)) / 3
    }

    /// A version's title (`new`) against the page's now (`old`), word by word — nil when they read the same (spaces at
    /// the ends aside). An emptied title is all removed, a title given since all added.
    public static func title(old: String, new: String) -> [DiffRun]? {
        let a = old.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard a != b else { return nil }
        return words(old: a, new: b)
    }

    /// The text of `new` with what `old` had and it hasn't put back in place: removed runs before added ones.
    public static func words(old: String, new: String) -> [DiffRun] {
        let a = tokens(old)
        let b = tokens(new)
        let difference = b.difference(from: a)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var runs: [DiffRun] = []
        func append(_ text: String, _ change: DiffChange) {
            if let last = runs.last, last.change == change {
                runs[runs.count - 1].text += text
            } else {
                runs.append(DiffRun(text, change))
            }
        }
        var i = 0
        var j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, !removed.contains(i), !inserted.contains(j) {
                append(b[j], .same)
                i += 1
                j += 1
                continue
            }
            var progressed = false
            while i < a.count, removed.contains(i) {
                append(a[i], .removed)
                i += 1
                progressed = true
            }
            while j < b.count, inserted.contains(j) {
                append(b[j], .added)
                j += 1
                progressed = true
            }
            if !progressed {
                if i < a.count {
                    append(a[i], .removed)
                    i += 1
                }
                if j < b.count {
                    append(b[j], .added)
                    j += 1
                }
            }
        }
        return runs
    }

    /// Words, runs of whitespace and single punctuation marks; CJK characters one each (no spaces separate them).
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var word = ""
        var space = ""
        func flush() {
            if !word.isEmpty {
                out.append(word)
                word = ""
            }
            if !space.isEmpty {
                out.append(space)
                space = ""
            }
        }
        for character in text {
            if character.isWhitespace {
                if !word.isEmpty {
                    out.append(word)
                    word = ""
                }
                space.append(character)
            } else if isCJK(character) || (character.isPunctuation || character.isSymbol) {
                flush()
                out.append(String(character))
            } else {
                if !space.isEmpty {
                    out.append(space)
                    space = ""
                }
                word.append(character)
            }
        }
        flush()
        return out
    }

    private static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return true
        default: return false
        }
    }
}
