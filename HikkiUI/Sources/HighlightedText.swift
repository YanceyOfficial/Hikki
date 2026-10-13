import SwiftUI

/// Text with every occurrence of each of `terms` emphasized (search results); case and accents don't matter.
public struct HighlightedText: View {
    private let text: String
    private let terms: [String]

    public init(_ text: String, terms: [String]) {
        self.text = text
        self.terms = terms
    }

    /// One query, split on whitespace.
    public init(_ text: String, query: String) {
        self.init(text, terms: query.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    public var body: some View {
        Text(attributed)
    }

    var attributed: AttributedString {
        var result = AttributedString(text)
        for range in Self.ranges(in: text, terms: terms) {
            guard let lower = AttributedString.Index(range.lowerBound, within: result),
                let upper = AttributedString.Index(range.upperBound, within: result)
            else { continue }
            result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            result[lower..<upper].foregroundColor = Theme.foreground
        }
        return result
    }

    /// Where the terms occur, in order, merged where they overlap.
    static func ranges(in text: String, terms: [String]) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for term in terms where !term.isEmpty {
            var from = text.startIndex
            while from < text.endIndex,
                let range = text.range(
                    of: term, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex),
                !range.isEmpty
            {
                found.append(range)
                from = range.upperBound
            }
        }
        found.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in found {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.s2) {
        HighlightedText("The roadmap is due Friday, after the café review", terms: ["roadmap", "friday", "cafe"])
        HighlightedText("Weekly sync", query: "week sy")
    }
    .padding()
}
