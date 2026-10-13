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

    @Test func segmentsReadOnlyTheKanji() {
        typealias S = JapaneseReading.Segment
        #expect(
            JapaneseReading.segments(for: "役に立ちます") == [
                S(text: "役", reading: "やく"), S(text: "に"), S(text: "立", reading: "た"), S(text: "ちます"),
            ])
        #expect(JapaneseReading.segments(for: "食べ物") == [S(text: "食", reading: "た"), S(text: "べ"), S(text: "物", reading: "もの")])
        #expect(JapaneseReading.segments(for: "漢字") == [S(text: "漢字", reading: "かんじ")])
        #expect(
            JapaneseReading.segments(for: "東京へ行く") == [
                S(text: "東京", reading: "とうきょう"), S(text: "へ"), S(text: "行", reading: "い"), S(text: "く"),
            ])
    }

    @Test func segmentsNeedKanjiAndKeepPunctuation() {
        #expect(JapaneseReading.segments(for: "かな") == nil)
        #expect(JapaneseReading.segments(for: "hello") == nil)
        #expect(JapaneseReading.segments(for: "々") == nil)  // the tokenizer has no kana for it alone
        let bare = JapaneseReading.segments(for: "漢字、かな")?.filter { $0.reading == nil }.map(\.text)
        #expect(bare == ["、かな"])
    }
}
