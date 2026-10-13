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

    /// A run of text: kanji with their reading, or kana/punctuation left bare.
    public struct Segment: Equatable, Sendable {
        public var text: String
        public var reading: String?

        public init(text: String, reading: String? = nil) {
            self.text = text
            self.reading = reading
        }
    }

    /// The reading laid over the kanji only: each word's own kana (okurigana, particles) are matched
    /// against its reading and left bare, so 役に立ちます reads 役(やく)に立(た)ちます. nil without kanji.
    public static func segments(for text: String) -> [Segment]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.contains(where: isKanji) else { return nil }
        let locale = NSLocale(localeIdentifier: "ja") as CFLocale
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, trimmed as CFString, CFRange(location: 0, length: trimmed.utf16.count),
            kCFStringTokenizerUnitWord | kCFStringTokenizerAttributeLatinTranscription, locale)
        var out: [Segment] = []
        func push(_ segment: Segment) {
            if segment.reading == nil, let last = out.last, last.reading == nil {
                out[out.count - 1].text += segment.text
            } else {
                out.append(segment)
            }
        }
        let source = trimmed as NSString
        var consumed = 0
        var kind = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while !kind.isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            // Whitespace and punctuation between words are kept as they are.
            if range.location > consumed {
                push(Segment(text: source.substring(with: NSRange(location: consumed, length: range.location - consumed))))
            }
            consumed = range.location + range.length
            let token = source.substring(with: NSRange(location: range.location, length: range.length))
            if token.unicodeScalars.contains(where: isKanji),
                let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription)
                    as? String
            {
                let kana = NSMutableString(string: latin)
                CFStringTransform(kana, nil, kCFStringTransformLatinHiragana, false)
                for segment in align(token, reading: kana as String) { push(segment) }
            } else {
                push(Segment(text: token))
            }
            kind = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        if consumed < source.length { push(Segment(text: source.substring(from: consumed))) }
        return out.contains { $0.reading != nil } ? out : nil
    }

    /// Splits a word into kanji runs and other runs, and gives each kanji run its share of the reading by
    /// matching the other runs literally (`(.+?)` for each kanji run). When that fails — or the tokenizer
    /// produced something that isn't kana (々 on its own) — the word takes the whole reading, or none.
    static func align(_ token: String, reading: String) -> [Segment] {
        guard reading.unicodeScalars.allSatisfy(isKana) else { return [Segment(text: token)] }
        var runs: [(text: String, kanji: Bool)] = []
        for scalar in token.unicodeScalars {
            let kanji = isKanji(scalar)
            if let last = runs.last, last.kanji == kanji {
                runs[runs.count - 1].text.unicodeScalars.append(scalar)
            } else {
                runs.append((String(scalar), kanji))
            }
        }
        guard runs.count > 1 else { return [Segment(text: token, reading: reading)] }
        let pattern =
            "^" + runs.map { $0.kanji ? "(.+?)" : NSRegularExpression.escapedPattern(for: hiraganaForm($0.text)) }.joined() + "$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: reading, range: NSRange(reading.startIndex..., in: reading))
        else { return [Segment(text: token, reading: reading)] }
        var segments: [Segment] = []
        var capture = 1
        for run in runs {
            if run.kanji {
                guard let found = Range(match.range(at: capture), in: reading) else {
                    return [Segment(text: token, reading: reading)]
                }
                segments.append(Segment(text: run.text, reading: String(reading[found])))
                capture += 1
            } else {
                segments.append(Segment(text: run.text))
            }
        }
        return segments
    }

    /// Katakana (and half-width forms) as hiragana, for matching a word's own kana against its reading.
    static func hiraganaForm(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformFullwidthHalfwidth, true)
        CFStringTransform(mutable, nil, kCFStringTransformHiraganaKatakana, true)
        return mutable as String
    }

    static func isKanji(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F, 0x3005: true  // 々 counts as kanji
        default: false
        }
    }

    static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F, 0x30FC: true  // incl. ー
        default: false
        }
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
