import CryptoKit
import Foundation

/// A page cut into passages short enough for a small embedding model (multilingual-e5-small reads 512 tokens; a CJK
/// character is about one): whole lines gathered up to `limit` characters, a longer line cut at sentence ends where it
/// can. Each passage starts with the page title, so a passage about "the budget" still knows it is in "Trip to Kyoto".
public enum Chunker {
    public struct Chunk: Sendable, Equatable {
        public var ordinal: Int
        public var text: String
        /// Identifies the text: an unchanged passage keeps its vector when the page is embedded again.
        public var hash: String
    }

    public static let limit = 400

    public static func chunks(title: String, headings: [String] = [], text: String, limit: Int = limit) -> [Chunk] {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // A page that is only a title (or only headings) still gets one passage.
        if lines.isEmpty { lines = headings.filter { !$0.isEmpty } }
        var passages: [String] = []
        var current = ""
        for line in lines.flatMap({ pieces(of: $0, limit: limit) }) {
            if !current.isEmpty && current.count + 1 + line.count > limit {
                passages.append(current)
                current = ""
            }
            current += current.isEmpty ? line : "\n" + line
        }
        if !current.isEmpty { passages.append(current) }
        if passages.isEmpty && !heading.isEmpty { passages = [""] }
        return passages.enumerated().map { ordinal, passage in
            let text = heading.isEmpty ? passage : passage.isEmpty ? heading : heading + "\n" + passage
            return Chunk(ordinal: ordinal, text: text, hash: hash(text))
        }
    }

    /// A line longer than `limit`, cut after sentence ends (. ! ? 。！？) where possible, else at `limit`.
    static func pieces(of line: String, limit: Int) -> [String] {
        guard line.count > limit else { return [line] }
        var out: [String] = []
        var rest = Substring(line)
        while rest.count > limit {
            let window = rest.prefix(limit)
            let cut =
                window.lastIndex(where: { "。！？.!?".contains($0) }).map { rest.index(after: $0) } ?? window.endIndex
            let piece = rest[..<cut].trimmingCharacters(in: .whitespaces)
            if !piece.isEmpty { out.append(piece) }
            rest = rest[cut...]
        }
        let tail = rest.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { out.append(tail) }
        return out
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
