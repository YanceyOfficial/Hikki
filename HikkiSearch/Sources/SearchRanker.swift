import Foundation

/// Orders search results — the title first, then the headings, then the page text, recent pages ahead on
/// ties — and cuts the excerpt a result shows. Pure, so the order is testable without an index.
public enum SearchRanker {
    /// What a page offers the ranker.
    public struct Page: Sendable {
        public var title: String
        /// `Pinyin.searchKey(for: title)` — "chanpinluxiantu cplxt" — or "" for a title without Han characters.
        public var titlePinyin: String
        /// The page's headings, one per line.
        public var headings: String
        public var text: String
        public var updatedAt: Date
        /// 0…40 from the index's BM25 order among the query's candidates (the best gets 40); 0 without an index.
        public var textRank: Int

        public init(
            title: String, titlePinyin: String = "", headings: String = "", text: String = "",
            updatedAt: Date = .distantPast, textRank: Int = 0
        ) {
            self.title = title
            self.titlePinyin = titlePinyin
            self.headings = headings
            self.text = text
            self.updatedAt = updatedAt
            self.textRank = textRank
        }
    }

    /// nil when no term occurs in the title (also by pinyin), the headings or the text. Higher is better.
    public static func score(_ query: SearchQuery, _ page: Page, now: Date = .now) -> Int? {
        guard !query.isEmpty else { return nil }
        let title = titleScore(query, page)
        let headings =
            page.headings.isEmpty
            ? 0 : termsScore(query.terms, in: SearchQuery.fold(page.headings), wordStarts: 320, anywhere: 300, each: 80)
        let text = textScore(query, SearchQuery.fold(page.text))
        guard title > 0 || headings > 0 || text > 0 else { return nil }
        let rank = headings > 0 || text > 0 ? page.textRank : 0
        return title + headings + text + rank + recency(page.updatedAt, now: now)
    }

    /// The whole title (1000), its start (700), every term at a word start (500) or anywhere in it (400), some of
    /// the terms (60 each); the pinyin keys the same way a step lower; failing all that, an fzf-style subsequence
    /// ("wkly" → Weekly) for the quick switcher.
    static func titleScore(_ query: SearchQuery, _ page: Page) -> Int {
        let title = SearchQuery.fold(page.title)
        guard !title.isEmpty else { return 0 }
        let joined = query.joined
        if title == joined { return 1000 }
        if title.hasPrefix(joined) { return 700 }
        var score = termsScore(query.terms, in: title, wordStarts: 500, anywhere: 400, each: 60)
        if score < 400, !page.titlePinyin.isEmpty, query.terms.allSatisfy({ $0.allSatisfy(\.isASCII) }) {
            // "chanpinluxiantu cplxt": a term at the start of either key (chanpin, cplxt) or inside one (lxt).
            score = max(score, termsScore(query.terms, in: page.titlePinyin, wordStarts: 450, anywhere: 350, each: 40))
        }
        if score == 0 {
            let fuzzy = [page.title, page.titlePinyin].compactMap { $0.isEmpty ? nil : FuzzyMatch.score(joined, in: $0) }.max()
            if let fuzzy { score = 100 + max(0, min(fuzzy, 400)) / 4 }
        }
        return score
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

    /// Every term in the (folded) text (250) or some of them (50 each); how well beyond that is the index's
    /// BM25 order (`Page.textRank`).
    static func textScore(_ query: SearchQuery, _ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let found = query.terms.count { text.contains($0) }
        guard found > 0 else { return 0 }
        return found == query.terms.count ? 250 : found * 50
    }

    /// Edited today, this week, this month: a little ahead.
    static func recency(_ updatedAt: Date, now: Date) -> Int {
        let age = now.timeIntervalSince(updatedAt)
        if age < 86_400 { return 30 }
        if age < 7 * 86_400 { return 15 }
        if age < 30 * 86_400 { return 5 }
        return 0
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
