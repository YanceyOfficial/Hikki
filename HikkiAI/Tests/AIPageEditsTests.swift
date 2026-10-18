import Testing

@testable import HikkiAI

struct AIPageEditsTests {
    private let answer = """
        我改了两处：动词的说法和一个错字。

        ```hikki-changes
        {"changes":[
          {"kind":"rewrite","block":"b3","html":"系动词可表<strong>状态</strong>或变化","title":"系动词不都是静态","why":"turn 表示变化"},
          {"kind":"insert","after":"b5","type":"heading2","html":"怎么判断","title":"补一个小节"},
          {"kind":"move","block":"b6","after":null,"title":"放到最前"},
          {"kind":"delete","block":"b7","title":"删掉重复"},
          {"kind":"rewrite","block":"b3","html":"again","title":"same block twice"},
          {"kind":"rewrite","block":"nope","html":"x","title":"unknown block"},
          {"kind":"insert","after":"b5","html":"","title":"empty insert"},
          {"kind":"move","block":"b5","after":"b5","title":"after itself"},
          {"kind":"explode","block":"b5","title":"unknown kind"},
          {"kind":"insert","after":"b6","type":"table","html":"<em>新</em>","title":"odd type"}
        ]}
        ```
        """

    @Test func theChatShowsTheAnswerWithoutItsChanges() {
        #expect(AIPageEdits.prose(answer) == "我改了两处：动词的说法和一个错字。")
        #expect(AIPageEdits.hasChanges(answer))
        // While streaming: a fence line still being typed is held back (a bare ``` may close a code block).
        #expect(AIPageEdits.prose("改好了。\n\n```hikki-ch") == "改好了。")
        #expect(AIPageEdits.prose("Code:\n```swift\nlet a = 1\n```") == "Code:\n```swift\nlet a = 1\n```")
        #expect(AIPageEdits.prose("No changes here.") == "No changes here.")
    }

    @Test func onlyChangesThatFitThePageAreKept() {
        let changes = AIPageEdits.changes(in: answer, blocks: ["b3", "b5", "b6", "b7"])
        #expect(changes.map(\.kind) == ["rewrite", "insert", "move", "delete", "insert"])
        #expect(
            changes[0]
                == ProposedPageChange(
                    kind: "rewrite", block: "b3", html: "系动词可表<strong>状态</strong>或变化", title: "系动词不都是静态", why: "turn 表示变化"))
        #expect(changes[1].after == "b5" && changes[1].type == "heading2" && changes[1].block == nil)
        #expect(changes[2].block == "b6" && changes[2].after == nil && changes[2].html == nil)
        #expect(changes[4].type == "paragraph")
    }

    @Test func anUnreadableBlockProposesNothing() {
        #expect(AIPageEdits.changes(in: "```hikki-changes\n{\"changes\": [", blocks: ["b1"]).isEmpty)
        #expect(AIPageEdits.changes(in: "Just prose.", blocks: ["b1"]).isEmpty)
        #expect(AIPageEdits.changes(in: "```hikki-changes\n[1,2]\n```", blocks: ["b1"]).isEmpty)
    }

    @Test func thePageGoesAsBlocksUpToTheBudget() {
        let blocks = [["id": "a", "type": "paragraph", "html": "one"], ["id": "b", "type": "heading1", "html": "two"]]
        let json = AIPageEdits.pageJSON(blocks, budget: 1000)
        #expect(json.contains("\"id\":\"a\"") && json.contains("\"id\":\"b\""))
        let cut = AIPageEdits.pageJSON(blocks, budget: 45)
        #expect(cut.contains("\"id\":\"a\"") && !cut.contains("\"id\":\"b\""))
    }

    @Test func blocksMakeTheChatAbleToEdit() {
        let model = AIModelCatalog.sonnet
        let plain = AIPrompts.chat([.user("hi")], pages: [(title: "T", text: "body")], model: model, webSearch: false)
        #expect(!plain.instructions.contains("hikki-changes"))
        let editable = AIPrompts.chat(
            [.user("fix it")], pages: [(title: "T", text: "body")], openPageBlocks: "{\"blocks\":[]}", model: model,
            webSearch: false)
        #expect(editable.instructions.contains("hikki-changes"))
        guard case .text(let context) = editable.messages[0].parts[0] else {
            Issue.record("no page context")
            return
        }
        #expect(context.contains("{\"blocks\":[]}") && !context.contains("body"))
    }
}
