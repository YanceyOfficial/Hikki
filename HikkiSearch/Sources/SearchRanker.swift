import Foundation

/// Orders search results — the title first, then the headings, then the page text, then attached files, recent
/// pages ahead on ties — and cuts the excerpt a result shows. Pure, so the order is testable without an index.
public enum SearchRanker {
    /// What a page offers the ranker: its title, and how many of the query's terms the index found where.
    public struct Page: Sendable {
        /// The title as `SearchQuery.fold` gives it.
        public var foldedTitle: String
        /// `Pinyin.searchKey(for: title)` — "chanpinluxiantu cplxt" — or "" for a title without Han characters.
        public var titlePinyin: String
        /// Terms found in a heading.
        public var headingTerms: Int
        /// Terms found anywhere in the page's text (headings included).
        public var textTerms: Int
        /// Terms found in the attached file that matched best.
        public var fileTerms: Int
        public var updatedAt: Date
        /// 0…40 from the index's BM25 order among the query's text matches (the best gets 40); 0 without an index.
        public var textRank: Int

        public init(
            foldedTitle: String, titlePinyin: String = "", headingTerms: Int = 0, textTerms: Int = 0, fileTerms: Int = 0,
            updatedAt: Date = .distantPast, textRank: Int = 0
        ) {
            self.foldedTitle = foldedTitle
            self.titlePinyin = titlePinyin
            self.headingTerms = headingTerms
            self.textTerms = textTerms
            self.fileTerms = fileTerms
            self.updatedAt = updatedAt
            self.textRank = textRank
        }
    }

    /// nil when no term occurs in the title (also by pinyin), the headings, the text or an attachment — only those
    /// the scope looks at (titles; headings and text; attachments; or all) — and the title isn't a close enough
    /// subsequence of the query either. Higher is better.
    public static func score(_ query: SearchQuery, _ page: Page, scope: SearchScope = .all, now: Date = .now) -> Int? {
        guard !query.isEmpty else { return nil }
        let looksAtTitle = scope == .all || scope == .titles
        let looksAtText = scope == .all || scope == .text
        let looksAtFiles = scope == .all || scope == .files
        let count = query.terms.count
        let title = looksAtTitle ? titleScore(query, page) : 0
        let headings = looksAtText ? found(page.headingTerms, of: count, all: 300, each: 80) : 0
        let text = looksAtText ? found(page.textTerms, of: count, all: 250, each: 50) : 0
        // Text inside an attached file: a step below the page's own.
        let file = looksAtFiles ? found(page.fileTerms, of: count, all: 200, each: 40) : 0
        var total = title + headings + text + file
        if total == 0 {
            // Nothing holds a term: the quick switcher's loose match on the title, if it is a close one.
            guard looksAtTitle, let fuzzy = fuzzyTitleScore(query, page) else { return nil }
            total = fuzzy
        }
        let rank = headings > 0 || text > 0 ? page.textRank : 0
        return total + rank + recency(page.updatedAt, now: now)
    }

    /// The whole title (1000), its start (700), every term at a word start (500) or anywhere in it (400), some of
    /// the terms (60 each); the pinyin keys the same way a step lower.
    static func titleScore(_ query: SearchQuery, _ page: Page) -> Int {
        let title = page.foldedTitle
        guard !title.isEmpty else { return 0 }
        let joined = query.joined
        if title == joined { return 1000 }
        if title.hasPrefix(joined) { return 700 }
        var score = termsScore(query.terms, in: title, wordStarts: 500, anywhere: 400, each: 60)
        if score < 400, !page.titlePinyin.isEmpty, query.terms.allSatisfy({ $0.allSatisfy(\.isASCII) }) {
            // "chanpinluxiantu cplxt": a term at the start of either key (chanpin, cplxt) or inside one (lxt).
            score = max(score, termsScore(query.terms, in: page.titlePinyin, wordStarts: 450, anywhere: 350, each: 40))
        }
        return score
    }

    /// An fzf-style subsequence of the title or its pinyin ("wkly" → Weekly): 100…200, nil for a query under three
    /// characters or a loose match (scattered letters, mid-word) — two letters are a subsequence of most titles.
    static func fuzzyTitleScore(_ query: SearchQuery, _ page: Page) -> Int? {
        let letters = query.joined.filter { !$0.isWhitespace }.count
        guard letters >= 3 else { return nil }
        let best = [page.foldedTitle, page.titlePinyin].compactMap { $0.isEmpty ? nil : FuzzyMatch.score(query.joined, in: $0) }
            .max()
        // A letter on its own scores 10 (less the length difference); a run or a word start 40–60 or more.
        guard let best, best >= letters * 25 else { return nil }
        return 100 + min(best, 400) / 4
    }

    /// `all` when every term was found, `each` per term otherwise, 0 for none.
    static func found(_ terms: Int, of count: Int, all: Int, each: Int) -> Int {
        terms >= count ? all : terms * each
    }

    /// `wordStarts` when every term starts a word of `text`, `anywhere` when every term is somewhere in it,
    /// `each` per term found otherwise.
    static func termsScore(_ terms: [String], in text: String, wordStarts: Int, anywhere: Int, each: Int) -> Int {
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        var starts = 0
        var inside = 0
        for term in terms {
            if words.contains(where: { $0.hasPrefix(term) }) {
                starts += 1
            } else if text.contains(term) {
                inside += 1
            }
        }
        if starts == terms.count { return wordStarts }
        if starts + inside == terms.count { return anywhere }
        return (starts + inside) * each
    }

    /// Edited today, this week, this month: a little ahead.
    static func recency(_ updatedAt: Date, now: Date) -> Int {
        let age = now.timeIntervalSince(updatedAt)
        if age < 86_400 { return 30 }
        if age < 7 * 86_400 { return 15 }
        if age < 30 * 86_400 { return 5 }
        return 0
    }

    /// The block a result shows and opens at, among blocks given folded: the one holding the most terms; among
    /// those a heading ahead of body text, then one that starts with a term ("ので表示理由" for ので), then the
    /// earliest. nil when no block holds one.
    public static func bestBlock(_ terms: [String], in blocks: [(folded: String, isHeading: Bool)]) -> Int? {
        var best: (index: Int, score: Int)?
        for (index, block) in blocks.enumerated() {
            let found = terms.count { block.folded.contains($0) }
            guard found > 0 else { continue }
            let score = found * 100 + (block.isHeading ? 40 : 0) + (terms.contains { block.folded.hasPrefix($0) } ? 20 : 0)
            if best == nil || score > best!.score { best = (index, score) }
        }
        return best?.index
    }

    /// The text around the first term that occurs in it, about `width` characters, cut at word boundaries where
    /// one is near, with an ellipsis for each cut side; "" when no term occurs.
    public static func snippet(of text: String, terms: [String], width: Int = 100) -> String {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let hits = terms.compactMap { text.range(of: $0, options: options) }
        guard let first = hits.min(by: { $0.lowerBound < $1.lowerBound }) else { return "" }
        var start = text.index(first.lowerBound, offsetBy: -(width / 3), limitedBy: text.startIndex) ?? text.startIndex
        var end = text.index(start, offsetBy: width, limitedBy: text.endIndex) ?? text.endIndex
        if end < first.upperBound { end = first.upperBound }
        if start > text.startIndex, let space = text[start..<first.lowerBound].firstIndex(where: \.isWhitespace),
            text.distance(from: start, to: space) <= 12
        {
            start = text.index(after: space)
        }
        if end < text.endIndex, let space = text[first.upperBound..<end].lastIndex(where: \.isWhitespace),
            text.distance(from: space, to: end) <= 12
        {
            end = space
        }
        let body = text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (start > text.startIndex ? "…" : "") + body + (end < text.endIndex ? "…" : "")
    }
}
