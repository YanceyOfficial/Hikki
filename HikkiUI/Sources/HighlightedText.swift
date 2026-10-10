import SwiftUI

/// Text with every case-insensitive occurrence of `query` emphasized (search results).
public struct HighlightedText: View {
    private let text: String
    private let query: String

    public init(_ text: String, query: String) {
        self.text = text
        self.query = query
    }

    public var body: some View {
        Text(attributed)
    }

    var attributed: AttributedString {
        var result = AttributedString(text)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return result }
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            if let lower = AttributedString.Index(range.lowerBound, within: result),
                let upper = AttributedString.Index(range.upperBound, within: result)
            {
                result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
                result[lower..<upper].foregroundColor = Theme.foreground
            }
            searchRange = range.upperBound..<text.endIndex
        }
        return result
    }
}
