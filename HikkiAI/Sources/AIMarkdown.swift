import Foundation

/// A model's answer as styled text (the Ask AI chat). The answer is untrusted: inline Markdown only, and a link stays
/// a link only when it goes to a web page — `hikki://`, `tel:`, other apps' schemes and the like become plain text,
/// so tapping an answer can't open a page, place a call or drive another app.
public enum AIMarkdown {
    /// One block of an answer: a paragraph, or an item of a bulleted or numbered list (its marker kept: "1.").
    public struct Block: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case paragraph
            case bullet
            case numbered(String)
        }
        public let kind: Kind
        public let text: AttributedString
    }

    /// The answer split into blocks (blank lines end a paragraph; "- ", "* " and "1. " start list items), each block's
    /// text styled as `attributed` does. Lines of one paragraph are joined by line breaks, as written.
    public static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(Block(kind: .paragraph, text: attributed(paragraph.joined(separator: "\n")))) }
            paragraph = []
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let item = listItem(line) {
                flush()
                blocks.append(Block(kind: item.kind, text: attributed(item.text)))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    private static func listItem(_ line: String) -> (kind: Block.Kind, text: String)? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return (.bullet, String(line.dropFirst(marker.count)))
        }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 3, line.dropFirst(digits.count).hasPrefix(". ") {
            return (.numbered("\(digits)."), String(line.dropFirst(digits.count + 2)))
        }
        return nil
    }

    public static func attributed(_ text: String) -> AttributedString {
        var styled =
            (try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)))
            ?? AttributedString(text)
        for run in styled.runs {
            guard let link = run.link else { continue }
            if !isWebLink(link) { styled[run.range].link = nil }
        }
        return styled
    }

    static func isWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return url.host() != nil
    }
}
