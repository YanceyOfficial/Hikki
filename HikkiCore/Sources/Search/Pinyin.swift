import Foundation

/// Pinyin search keys so "luxiantu" and "lxt" both find "路线图".
public enum Pinyin {
    /// "Weekly 路线图" → "weeklyluxiantu wlxt". Empty when the text has no Han characters
    /// (plain Latin titles are already matched directly).
    public static func searchKey(for text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.properties.isIdeographic }) else { return "" }
        guard
            let latin = text.applyingTransform(.mandarinToLatin, reverse: false)?
                .applyingTransform(.stripDiacritics, reverse: false)?
                .lowercased()
        else { return "" }
        let syllables = latin.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let full = syllables.joined()
        let initials = String(syllables.compactMap(\.first))
        return "\(full) \(initials)"
    }
}
