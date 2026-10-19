import Foundation

/// The chat's thinking timeline: what a stretch of the model's thinking is called in its row (and in the header while
/// it streams) — the bold title the summaries open with ("**Checking the dates**"), else its first line.
public enum AIThinking {
    /// Longest title kept (characters).
    static let maxTitle = 80

    public static func title(of text: String) -> String? {
        if let match = text.firstMatch(of: /\*\*(.+?)\*\*/) {
            let bold = match.1.trimmingCharacters(in: .whitespaces)
            if !bold.isEmpty { return String(bold.prefix(maxTitle)) }
        }
        let line = text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line.map { String($0.replacingOccurrences(of: "**", with: "").prefix(maxTitle)) }
    }

    /// The thinking's text without the title line it opens with (the row shows the title above it).
    public static func body(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.prefixMatch(of: /\*\*(.+?)\*\*[ \t]*\n?/) else { return trimmed }
        return String(trimmed[match.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
