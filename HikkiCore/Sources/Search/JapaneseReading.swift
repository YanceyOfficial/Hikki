import Foundation

/// Readings (furigana) for Japanese text from the system's tokenizer: its Latin transcription of each word,
/// turned back into hiragana. Offline, no dictionary of our own; good for a first suggestion the user can edit.
public enum JapaneseReading {
    /// The hiragana reading of `text`, or nil when it holds no Japanese (kanji or kana) — Latin text would
    /// otherwise come back as nonsense kana.
    public static func hiragana(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.contains(where: isJapanese) else { return nil }
        let locale = NSLocale(localeIdentifier: "ja") as CFLocale
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, trimmed as CFString, CFRange(location: 0, length: trimmed.utf16.count),
            kCFStringTokenizerUnitWord | kCFStringTokenizerAttributeLatinTranscription, locale)
        var reading = ""
        var kind = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while !kind.isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let token = (trimmed as NSString).substring(with: NSRange(location: range.location, length: range.length))
            if token.unicodeScalars.contains(where: isJapanese),
                let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            {
                let kana = NSMutableString(string: latin)
                CFStringTransform(kana, nil, kCFStringTransformLatinHiragana, false)
                reading += kana as String
            } else {
                reading += token  // punctuation, numbers, Latin: as they are
            }
            kind = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        return reading.isEmpty || reading == trimmed ? nil : reading
    }

    /// Kanji, hiragana or katakana (the half-width forms too).
    static func isJapanese(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: true  // kana
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: true  // Han
        default: false
        }
    }
}
