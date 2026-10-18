import Foundation
import Markdown

/// A model's answer as blocks of styled text (the Ask AI chat): GitHub-flavoured Markdown read by swift-markdown
/// (cmark-gfm) — headings, nested and numbered lists, task items, quotes, fenced code, tables, rules — the way
/// exodus-ios's MarkdownKit reads it (`Sources/MarkdownKit/MarkdownParser.swift`, whose inline builder and autolinks
/// this ports). The answer is untrusted: a link stays a link only when it goes to a web page — `hikki://`, `tel:`,
/// other apps' schemes and the like become plain text, so tapping an answer can't open a page, place a call or drive
/// another app. Pictures are never loaded: one shows as its description (a link when its address is a web page).
///
/// Streaming: the text may stop anywhere. cmark reads an unclosed fence as code running to the end, and a fence that
/// is still being typed (a last line of only backticks or tildes) is left out, so no stray marker flashes by.
public enum AIMarkdown {
    public indirect enum Block: Equatable, Sendable {
        case paragraph(AttributedString)
        /// Level 1–6.
        case heading(level: Int, text: AttributedString)
        case list(List)
        case quote([Block])
        /// The code as written (no final line break); the language as the fence names it, nil when it doesn't.
        case code(language: String?, code: String)
        case table(Table)
        case rule
    }

    public struct List: Equatable, Sendable {
        public let ordered: Bool
        /// The first item's number (an ordered list may start anywhere: "3.").
        public let start: Int
        public let items: [Item]

        public struct Item: Equatable, Sendable {
            /// A task item's box: true ticked, false open, nil an ordinary item.
            public let checked: Bool?
            public let blocks: [Block]
        }
    }

    public struct Table: Equatable, Sendable {
        public enum Alignment: Equatable, Sendable { case leading, center, trailing }
        /// One per column; nil when the delimiter row sets none.
        public let alignments: [Alignment?]
        public let header: [AttributedString]
        /// Rows as written: a row may have fewer cells than the header.
        public let rows: [[AttributedString]]
    }

    /// The answer as blocks. A single line break inside a paragraph stays a line break, as the model wrote it.
    public static func blocks(_ text: String) -> [Block] {
        let source = flankingCJKStrong(escapingLoneTildes(droppingPartialFence(text)))
        let document = Document(parsing: source, options: [.disableSmartOpts])
        return blocks(document.children)
    }

    /// Inline Markdown only, styled the same way (emphasis, code, web links): one paragraph's worth.
    public static func attributed(_ text: String) -> AttributedString {
        let blocks = blocks(text)
        var result = AttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 { result += AttributedString("\n") }
            switch block {
            case .paragraph(let text), .heading(_, let text): result += text
            default: result += AttributedString(plain(block))
            }
        }
        return result
    }

    static func isWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return url.host() != nil
    }

    // MARK: - Blocks

    private static func blocks(_ children: MarkupChildren) -> [Block] {
        children.compactMap(block)
    }

    private static func block(_ markup: Markup) -> Block? {
        switch markup {
        case let paragraph as Paragraph:
            let content = HTMLBreak.trimming(inline(paragraph.children))
            return content.characters.allSatisfy(\.isWhitespace) ? nil : .paragraph(content)
        case let heading as Heading:
            return .heading(level: min(max(heading.level, 1), 6), text: inline(heading.children))
        case let list as UnorderedList:
            return .list(List(ordered: false, start: 1, items: items(list.listItems)))
        case let list as OrderedList:
            return .list(List(ordered: true, start: Int(list.startIndex), items: items(list.listItems)))
        case let quote as BlockQuote:
            return .quote(blocks(quote.children))
        case let code as CodeBlock:
            let language = code.language?.trimmingCharacters(in: .whitespaces)
            return .code(language: language?.isEmpty == false ? language : nil, code: trimmingFinalNewline(code.code))
        case let table as Markdown.Table:
            return .table(self.table(table))
        case is ThematicBreak:
            return .rule
        case let html as HTMLBlock:
            // Shown as the text it is (a model's `<br>` as a line break), never interpreted.
            let text = HTMLBreak.replacing(in: trimmingFinalNewline(html.rawHTML))
            return text.allSatisfy(\.isWhitespace) ? nil : .paragraph(AttributedString(text))
        default:
            let text = markup.format()
            return text.isEmpty ? nil : .paragraph(AttributedString(text))
        }
    }

    private static func items(_ items: some Sequence<ListItem>) -> [List.Item] {
        items.map { item in
            let checked: Bool? =
                switch item.checkbox {
                case .checked: true
                case .unchecked: false
                case nil: nil
                }
            return List.Item(checked: checked, blocks: blocks(item.children))
        }
    }

    private static func table(_ table: Markdown.Table) -> Table {
        let alignments: [Table.Alignment?] = table.columnAlignments.map {
            switch $0 {
            case .left: .leading
            case .center: .center
            case .right: .trailing
            case nil: nil
            }
        }
        let header = table.head.cells.map { inline($0.children) }
        let rows = table.body.rows.map { row in Array(row.cells.map { inline($0.children) }) }
        return Table(alignments: alignments, header: Array(header), rows: Array(rows))
    }

    private static func trimmingFinalNewline(_ text: String) -> String {
        text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    /// A block's words without styling (for `attributed` given more than a paragraph).
    private static func plain(_ block: Block) -> String {
        switch block {
        case .paragraph(let text), .heading(_, let text): String(text.characters)
        case .list(let list): list.items.map { $0.blocks.map(plain).joined(separator: "\n") }.joined(separator: "\n")
        case .quote(let blocks): blocks.map(plain).joined(separator: "\n")
        case .code(_, let code): code
        case .table(let table):
            ([table.header] + table.rows).map { $0.map { String($0.characters) }.joined(separator: "\t") }
                .joined(separator: "\n")
        case .rule: ""
        }
    }

    static func inline(_ children: MarkupChildren) -> AttributedString {
        var builder = InlineBuilder()
        for child in children { builder.visit(child) }
        builder.flush()
        return builder.build()
    }

    // MARK: - Streaming and model habits

    /// A last line that is only the start of a fence (one or two backticks or tildes, or three still waiting for
    /// their line break) would show as stray characters until the next token: left out while it is written.
    static func droppingPartialFence(_ text: String) -> String {
        let lineStart = text.lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let line = text[lineStart...].drop { $0 == " " || $0 == ">" }
        guard !line.isEmpty, line.count <= 3, line.allSatisfy({ $0 == "`" }) || line.allSatisfy({ $0 == "~" }) else {
            return text
        }
        return String(text[..<lineStart])
    }

    /// GFM strikes text between single tildes, and models write "~5 min" for "about": a tilde that isn't part of a
    /// `~~` pair is escaped (never inside code — a fenced block or a backtick span keeps its tildes).
    static func escapingLoneTildes(_ text: String) -> String {
        guard text.contains("~") else { return text }
        var output = ""
        output.reserveCapacity(text.count + 8)
        var fence: (marker: Character, count: Int)?
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if index > 0 { output.append("\n") }
            let trimmed = line.drop { $0 == " " || $0 == ">" }
            if let marker = trimmed.first, marker == "`" || marker == "~" {
                let run = trimmed.prefix { $0 == marker }.count
                if run >= 3 {
                    if let open = fence {
                        if open.marker == marker, run >= open.count, trimmed.dropFirst(run).allSatisfy(\.isWhitespace) {
                            fence = nil
                        }
                    } else {
                        fence = (marker, run)
                    }
                    output += line
                    continue
                }
            }
            if fence != nil || !line.contains("~") {
                output += line
                continue
            }
            let chars = Array(line)
            var inCode = 0  // the backtick run that opened a code span, 0 outside one
            var i = 0
            while i < chars.count {
                let char = chars[i]
                if char == "\\", i + 1 < chars.count {
                    output.append(char)
                    output.append(chars[i + 1])
                    i += 2
                    continue
                }
                if char == "`" {
                    var run = 0
                    while i + run < chars.count, chars[i + run] == "`" { run += 1 }
                    if inCode == 0 {
                        inCode = run
                    } else if inCode == run {
                        inCode = 0
                    }
                    output += String(repeating: "`", count: run)
                    i += run
                    continue
                }
                // An autolink (`<https://host/~user>`) takes no escapes: kept as written.
                if char == "<", inCode == 0, let close = chars[i...].firstIndex(of: ">"),
                    !chars[i..<close].contains(where: \.isWhitespace)
                {
                    output += String(chars[i...close])
                    i = close + 1
                    continue
                }
                if char == "~", inCode == 0 {
                    var run = 0
                    while i + run < chars.count, chars[i + run] == "~" { run += 1 }
                    output += run == 2 ? "~~" : String(repeating: "\\~", count: run)
                    i += run
                    continue
                }
                output.append(char)
                i += 1
            }
        }
        return output
    }
}

extension AIMarkdown {
    /// Hair space: whitespace to cmark, so it makes a `**` beside it flank, and taken out of the text again.
    static let flankSpace: Character = "\u{200A}"

    /// cmark's flanking rules don't know CJK: a `**` that opens before punctuation right after a letter, or closes
    /// after punctuation right before a letter, isn't a delimiter — "**注意：**这是" and "看**“这个”**吧" stay literal, and
    /// a later `**` pairs with the wrong one. Chinese and Japanese answers hit it all the time. Each line's `**` runs
    /// (outside code) alternate opening and closing; one that wouldn't, beside a non-ASCII character, gets a hair space
    /// on the side that makes it — before an opener, after a closer. Latin text is left to cmark as written.
    static func flankingCJKStrong(_ text: String) -> String {
        guard text.contains("**"), text.unicodeScalars.contains(where: { !$0.isASCII }) else { return text }
        var output = ""
        output.reserveCapacity(text.count + 8)
        var fence: (marker: Character, count: Int)?
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if index > 0 { output.append("\n") }
            if let next = Fence.toggle(line, open: fence) {
                fence = next.marker.map { ($0, next.count) }
                output += line
                continue
            }
            guard fence == nil, line.contains("**") else {
                output += line
                continue
            }
            let chars = Array(line)
            var inCode = 0
            var opening = true
            var i = 0
            while i < chars.count {
                let char = chars[i]
                if char == "\\", i + 1 < chars.count {
                    output.append(char)
                    output.append(chars[i + 1])
                    i += 2
                    continue
                }
                if char == "`" {
                    var run = 0
                    while i + run < chars.count, chars[i + run] == "`" { run += 1 }
                    if inCode == 0 {
                        inCode = run
                    } else if inCode == run {
                        inCode = 0
                    }
                    output += String(repeating: "`", count: run)
                    i += run
                    continue
                }
                guard char == "*", inCode == 0 else {
                    output.append(char)
                    i += 1
                    continue
                }
                var run = 0
                while i + run < chars.count, chars[i + run] == "*" { run += 1 }
                let before = i > 0 ? chars[i - 1] : nil
                let after = i + run < chars.count ? chars[i + run] : nil
                if run == 2 {
                    if opening, let before, let after, isPunctuation(after), !before.isWhitespace, !isPunctuation(before),
                        !before.isASCII || !after.isASCII
                    {
                        output.append(flankSpace)
                        output += "**"
                    } else if !opening, let before, let after, isPunctuation(before), !after.isWhitespace,
                        !isPunctuation(after), !before.isASCII || !after.isASCII
                    {
                        output += "**"
                        output.append(flankSpace)
                    } else {
                        output += "**"
                    }
                    opening.toggle()
                } else {
                    output += String(repeating: "*", count: run)
                }
                i += run
            }
        }
        return output
    }

    /// cmark's punctuation: ASCII punctuation and Unicode's P categories (CJK 、。：“” 「」 included).
    private static func isPunctuation(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
            .finalPunctuation, .otherPunctuation:
            return true
        default:
            return scalar.isASCII && (char.isPunctuation || char.isSymbol)
        }
    }
}

/// Fenced code lines, shared by the line rewrites that must leave code alone.
enum Fence {
    /// For a fence line: the fence state after it (marker nil when it closed the open one); nil for any other line.
    static func toggle(_ line: Substring, open: (marker: Character, count: Int)?) -> (marker: Character?, count: Int)? {
        let trimmed = line.drop { $0 == " " || $0 == ">" }
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let run = trimmed.prefix { $0 == marker }.count
        guard run >= 3 else { return nil }
        if let open {
            if open.marker == marker, run >= open.count, trimmed.dropFirst(run).allSatisfy(\.isWhitespace) {
                return (nil, 0)
            }
            return (open.marker, open.count)
        }
        return (marker, run)
    }
}

/// `<br>`, `<br/>`, `<br />`, in any case: the one piece of HTML a model writes into Markdown as a matter of course,
/// and it means a line break. Every other tag is shown as the text it is. (exodus-ios, MarkdownParser.swift.)
enum HTMLBreak {
    nonisolated(unsafe) private static let tag = #/<br\s*/?>/#.ignoresCase()

    static func matches(_ html: String) -> Bool {
        html.trimmingCharacters(in: .whitespaces).wholeMatch(of: tag) != nil
    }

    static func replacing(in html: String) -> String {
        guard html.contains("<") else { return html }
        let replaced = html.replacing(tag, with: "\n")
        guard replaced != html else { return html }
        return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trimming(_ content: AttributedString) -> AttributedString {
        guard content.characters.first?.isNewline == true || content.characters.last?.isNewline == true else {
            return content
        }
        var content = content
        while content.characters.first?.isNewline == true { content.characters.removeFirst() }
        while content.characters.last?.isNewline == true { content.characters.removeLast() }
        return content
    }
}

/// Collects plain text and styled scalar ranges, then styles once (appending many small AttributedStrings is slow).
/// Links pass `AIMarkdown.isWebLink` or are dropped, their text kept. (exodus-ios, MarkdownParser.swift.)
private struct InlineBuilder {
    struct Run {
        let scalars: Int
        let intent: InlinePresentationIntent
        let link: URL?
    }

    var text = ""
    var runs: [Run] = []
    var intent: InlinePresentationIntent = []
    var link: URL?
    // cmark splits text at unmatched delimiters; autolinking needs the whole run.
    var pending = ""

    func build() -> AttributedString {
        var result = AttributedString(text)
        let scalars = result.unicodeScalars
        var index = scalars.startIndex
        for run in runs {
            let end = scalars.index(index, offsetBy: run.scalars)
            if !run.intent.isEmpty { result[index..<end].inlinePresentationIntent = run.intent }
            if let link = run.link { result[index..<end].link = link }
            index = end
        }
        if text.contains("**") { LeftoverStrong.apply(to: &result) }
        return result
    }

    mutating func visit(_ markup: Markup) {
        if let node = markup as? Markdown.Text {
            pending += node.string.filter { $0 != AIMarkdown.flankSpace }
            return
        }
        flush()
        switch markup {
        case is SoftBreak:
            append("\n")
        case is LineBreak:
            append("\n")
        case let code as InlineCode:
            with(.code) { $0.append(code.code) }
        case is Emphasis:
            with(.emphasized) { $0.visitChildren(markup) }
        case is Strong:
            with(.stronglyEmphasized) { $0.visitChildren(markup) }
        case is Strikethrough:
            with(.strikethrough) { $0.visitChildren(markup) }
        case let anchor as Markdown.Link:
            withLink(anchor.destination.flatMap(URL.init(string:))) { $0.visitChildren(markup) }
        case let image as Markdown.Image:
            withLink(image.source.flatMap(URL.init(string:))) { $0.append(image.plainText) }
        case let html as InlineHTML:
            append(HTMLBreak.matches(html.rawHTML) ? "\n" : html.rawHTML)
        default:
            if markup.childCount > 0 {
                visitChildren(markup)
            } else {
                append(markup.format())
            }
        }
    }

    mutating func visitChildren(_ markup: Markup) {
        for child in markup.children { visit(child) }
        flush()
    }

    mutating func flush() {
        guard !pending.isEmpty else { return }
        let text = pending
        pending = ""
        appendText(text)
    }

    mutating func with(_ added: InlinePresentationIntent, _ body: (inout InlineBuilder) -> Void) {
        let saved = intent
        intent.insert(added)
        body(&self)
        intent = saved
    }

    /// Inside a link that isn't a web page the text stays, without the link.
    mutating func withLink(_ url: URL?, _ body: (inout InlineBuilder) -> Void) {
        let saved = link
        link = url.flatMap { AIMarkdown.isWebLink($0) ? $0 : nil }
        body(&self)
        link = saved
    }

    mutating func append(_ string: String) {
        guard !string.isEmpty else { return }
        text += string
        let count = string.unicodeScalars.count
        if let last = runs.last, last.intent == intent, last.link == link {
            runs[runs.count - 1] = Run(scalars: last.scalars + count, intent: intent, link: link)
        } else {
            runs.append(Run(scalars: count, intent: intent, link: link))
        }
    }

    mutating func appendText(_ string: String) {
        guard link == nil, !intent.contains(.code) else { return append(string) }
        for (piece, url) in Autolink.split(string) {
            let saved = link
            link = url
            append(piece)
            link = saved
        }
    }
}

/// `**` that cmark left as text. Its flanking rules don't know CJK: a run that opens before or closes after
/// punctuation next to a letter isn't a delimiter, so "**注意：**这是" or "看**“这个”**吧" stays literal — Chinese and
/// Japanese answers hit it all the time. And while an answer streams, the closing `**` hasn't arrived yet. Leftover
/// markers outside code pair up in order and their text turns bold; a last one without a partner bolds to the end (as
/// it will be once the partner comes), or is dropped when it is the very end.
enum LeftoverStrong {
    static func apply(to string: inout AttributedString) {
        let markers = markerOffsets(string)
        guard !markers.isEmpty else { return }
        let length = string.characters.count
        var pairs: [(open: Int, close: Int?)] = []
        var index = 0
        while index < markers.count {
            let close = index + 1 < markers.count ? markers[index + 1] : nil
            pairs.append((markers[index], close))
            index += 2
        }
        // From the end, so earlier offsets stay valid as markers are removed.
        for pair in pairs.reversed() {
            let start = pair.open + 2
            let end = pair.close ?? length
            if end > start {
                let range = self.range(string, start, end)
                for (intent, runRange) in string[range].runs[\.inlinePresentationIntent].reversed() {
                    string[runRange].inlinePresentationIntent = (intent ?? []).union(.stronglyEmphasized)
                }
            } else if pair.close != nil {
                continue  // "****": nothing between, left as written
            }
            if let close = pair.close { string.removeSubrange(self.range(string, close, close + 2)) }
            string.removeSubrange(self.range(string, pair.open, pair.open + 2))
        }
    }

    /// Character offsets of each `**` (exactly two asterisks) outside code.
    private static func markerOffsets(_ string: AttributedString) -> [Int] {
        var offsets: [Int] = []
        var offset = 0
        for run in string.runs {
            let chars = Array(string[run.range].characters)
            defer { offset += chars.count }
            if run.inlinePresentationIntent?.contains(.code) == true || run.link != nil { continue }
            var i = 0
            while i < chars.count {
                guard chars[i] == "*" else {
                    i += 1
                    continue
                }
                var count = 0
                while i + count < chars.count, chars[i + count] == "*" { count += 1 }
                if count == 2 { offsets.append(offset + i) }
                i += count
            }
        }
        return offsets
    }

    private static func range(_ string: AttributedString, _ start: Int, _ end: Int) -> Range<AttributedString.Index> {
        let lower = string.characters.index(string.startIndex, offsetBy: start)
        return lower..<string.characters.index(lower, offsetBy: end - start)
    }
}

/// GFM's extended autolinks (swift-markdown doesn't enable cmark-gfm's extension): a bare `https://…`, `http://…` or
/// `www.…` in text becomes a link. (exodus-ios, MarkdownParser.swift.)
enum Autolink {
    private static let prefixes = [Array("https://"), Array("http://"), Array("www.")]

    static func split(_ text: String) -> [(String, URL?)] {
        guard text.contains("://") || text.localizedCaseInsensitiveContains("www.") else { return [(text, nil)] }
        let chars = Array(text)
        var pieces: [(String, URL?)] = []
        var plainStart = 0
        var index = 0
        while index < chars.count {
            let boundary = index == 0 || chars[index - 1].isWhitespace || "*_~(".contains(chars[index - 1])
            if boundary, let prefix = prefixLength(chars, at: index) {
                var end = index
                while end < chars.count, !chars[end].isWhitespace, chars[end] != "<" { end += 1 }
                end = trimmedEnd(chars, from: index, to: end)
                let token = String(chars[index..<end])
                let host = token.dropFirst(prefix)
                if host.contains("."), !host.hasPrefix("."),
                    let url = URL(string: prefix == 4 ? "http://" + token : token), AIMarkdown.isWebLink(url)
                {
                    if plainStart < index { pieces.append((String(chars[plainStart..<index]), nil)) }
                    pieces.append((token, url))
                    plainStart = end
                    index = end
                    continue
                }
            }
            index += 1
        }
        if plainStart < chars.count { pieces.append((String(chars[plainStart...]), nil)) }
        return pieces
    }

    private static func prefixLength(_ chars: [Character], at index: Int) -> Int? {
        for prefix in prefixes where index + prefix.count <= chars.count {
            if zip(chars[index..<(index + prefix.count)], prefix).allSatisfy({ $0.lowercased() == String($1) }) {
                return prefix.count
            }
        }
        return nil
    }

    private static func trimmedEnd(_ chars: [Character], from start: Int, to end: Int) -> Int {
        var end = end
        while end > start {
            let last = chars[end - 1]
            if "?!.,:*_~".contains(last) {
                end -= 1
            } else if last == ")",
                chars[start..<end].filter({ $0 == ")" }).count > chars[start..<end].filter({ $0 == "(" }).count
            {
                end -= 1
            } else {
                break
            }
        }
        return end
    }
}
