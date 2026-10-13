import Foundation
import Testing

@testable import HikkiCore

struct JapaneseReadingTests {
    @Test func readsKanjiAsHiragana() {
        #expect(JapaneseReading.hiragana(for: "漢字") == "かんじ")
        #expect(JapaneseReading.hiragana(for: "東京") == "とうきょう")
        // The tokenizer picks one of the two readings; either is right, and whitespace is trimmed.
        #expect(["にほんご", "にっぽんご"].contains(JapaneseReading.hiragana(for: " 日本語 ") ?? ""))
    }

    @Test func keepsKanaWordsAndMixedText() {
        // A verb with okurigana reads as a whole; kana stays kana.
        #expect(JapaneseReading.hiragana(for: "読む") == "よむ")
        #expect(JapaneseReading.hiragana(for: "東京へ行く") == "とうきょうへいく")
    }

    @Test func hasNothingForNonJapaneseText() {
        #expect(JapaneseReading.hiragana(for: "hello") == nil)
        #expect(JapaneseReading.hiragana(for: "123") == nil)
        #expect(JapaneseReading.hiragana(for: "") == nil)
        #expect(JapaneseReading.hiragana(for: "かな") == nil)  // already a reading
    }
}
