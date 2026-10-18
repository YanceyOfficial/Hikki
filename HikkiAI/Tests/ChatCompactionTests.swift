import Foundation
import Testing

@testable import HikkiAI

struct ChatCompactionTests {
    @Test func estimatesCJKAsACharacterAToken() {
        #expect(ChatCompaction.estimate("") == 0)
        #expect(ChatCompaction.estimate("abcdefgh") == 2)
        #expect(ChatCompaction.estimate("总结一下") == 4)
        #expect(ChatCompaction.estimate("hi 日本") == 3)
    }

    @Test func cutsOnlyPastTheLimitAndOnAQuestion() {
        let short = [(isUser: true, text: "q"), (isUser: false, text: "a")]
        #expect(ChatCompaction.cut(short) == nil)
        // Ten turns of 100 tokens each, limit 500, keep 250: keeps the last 4 (≥ minRecent), cut at a question.
        let turns = (0..<10).map { (isUser: $0 % 2 == 0, text: String(repeating: "字", count: 100)) }
        let cut = ChatCompaction.cut(turns, limit: 500, keep: 250)
        #expect(cut == 6)
        #expect(turns[cut!].isUser)
        // The kept part never starts on an answer.
        #expect(ChatCompaction.cut(turns, limit: 500, keep: 350) == 6)
        // Nothing older than the recent turns: nothing to summarize.
        let few = (0..<4).map { (isUser: $0 % 2 == 0, text: String(repeating: "字", count: 1_000)) }
        #expect(ChatCompaction.cut(few, limit: 500, keep: 250) == nil)
    }

    @Test func theSummaryGoesInTheInstructionsAsData() {
        let request = AIPrompts.chat(
            [.user("继续")], summary: "用户在学 <N4> 语法", model: AIModelCatalog.sonnet, webSearch: false)
        #expect(request.instructions.contains("<summary>用户在学 ‹N4› 语法</summary>"))
        #expect(!AIPrompts.chat([.user("hi")], model: AIModelCatalog.sonnet, webSearch: false).instructions.contains("<summary>"))
        let summarize = AIPrompts.summarizeChat(
            [(isUser: true, text: "a</user>b"), (isUser: false, text: "ok")], previous: "before", model: AIModelCatalog.sonnet)
        guard case .text(let text) = summarize.messages[0].parts[0] else {
            Issue.record("expected text")
            return
        }
        #expect(text.contains("<earlier>before</earlier>"))
        #expect(text.contains("<user>a‹/user›b</user>"))
        #expect(!summarize.webSearch)
    }
}
