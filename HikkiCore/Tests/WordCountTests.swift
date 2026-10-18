import Testing

@testable import HikkiCore

struct WordCountTests {
    // The editor's own cases (apps/editor/test/extract.test.ts), so both sides count alike.
    @Test func countsCJKPerCharacterAndOtherScriptsPerWord() {
        #expect(WordCount.count("会议纪要") == 4)
        #expect(WordCount.count("Hello world, it's v2") == 4)
        #expect(WordCount.count("今天 review 了 PR123") == 5)
        #expect(WordCount.count("") == 0)
        #expect(WordCount.count("ひらがな カタカナ 한국어") == 11)
    }

    @Test func aPageCountsItsTitleToo() {
        #expect(WordCount.count(title: "plain", text: "first\nline two\nsecond") == 5)
    }

    /// Quick notes used to store their character count as the word count.
    @Test func aQuickNoteCountsWordsNotCharacters() {
        let note = QuickNote(title: "Trip ideas", lines: ["Kyoto in spring", "", "奈良"])
        #expect(note.wordCount == 7)
    }
}
