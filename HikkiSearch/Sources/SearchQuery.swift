import Foundation

/// A search as typed: its terms, lowercased and without accents, in order, without repeats
/// ("Weekly  SYNC weekly" → weekly, sync).
public struct SearchQuery: Equatable, Sendable {
    public let terms: [String]

    public init(_ raw: String) {
        var seen = Set<String>()
        terms = Self.fold(raw).split(whereSeparator: \.isWhitespace).map(String.init).filter { seen.insert($0).inserted }
    }

    public var isEmpty: Bool { terms.isEmpty }

    /// The terms as one string, for whole-title comparisons.
    public var joined: String { terms.joined(separator: " ") }

    /// Case and accents don't matter: "cafe" finds Café. The index stores text folded the same way.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
