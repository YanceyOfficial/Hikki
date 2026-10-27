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

    /// "At the end of the page": `after: "end"` is the last of the page's blocks in reading order, and several inserts
    /// may share one `after` (they go in that order; the editor keeps each after the one before).
    @Test func endNamesThePagesLastBlockAndInsertsMayShareAnAfter() {
        let answer = """
            放在文章尾。

            ```hikki-changes
            {"changes":[
              {"kind":"insert","after":"end","type":"heading2","html":"区别","title":"小标题"},
              {"kind":"insert","after":"end","html":"第一段","title":"第一段"},
              {"kind":"insert","after":"end","html":"第二段","title":"第二段"},
              {"kind":"move","block":"b1","after":"end","title":"移到最后"}
            ]}
            ```
            """
        // Reading order, not alphabetical: the last block is b2.
        let changes = AIPageEdits.changes(in: answer, blocks: ["b3", "b1", "b2"])
        #expect(changes.map(\.kind) == ["insert", "insert", "insert", "move"])
        #expect(changes.map(\.after) == ["b2", "b2", "b2", "b2"])
        #expect(changes.map(\.html) == ["区别", "第一段", "第二段", nil])
        // A page with no blocks has no end.
        #expect(AIPageEdits.changes(in: answer, blocks: []).isEmpty)
        // A page whose last block is named "end" still reads it as the end (the move names b1, unknown there).
        #expect(AIPageEdits.changes(in: answer, blocks: ["end"]).map(\.after) == ["end", "end", "end"])
        #expect(AIPageEdits.instructions.contains("\"end\""))
    }

    @Test func thePageGoesAsBlocksUpToTheBudget() {
        let blocks = [["id": "a", "type": "paragraph", "html": "one"], ["id": "b", "type": "heading1", "html": "two"]]
        let json = AIPageEdits.pageJSON(blocks, budget: 1000)
        #expect(json.contains("\"id\":\"a\"") && json.contains("\"id\":\"b\""))
        #expect(!json.contains("omitted"))
        // Cut: the model is told how many blocks follow, so the page's end is not where the budget ran out.
        let cut = AIPageEdits.pageJSON(blocks + [["id": "c", "type": "paragraph", "html": "three"]], budget: 45)
        #expect(cut.contains("\"id\":\"a\"") && !cut.contains("\"id\":\"b\"") && !cut.contains("\"id\":\"c\""))
        #expect(cut.hasSuffix("\n],\"omitted\":2}"))
        #expect(AIPageEdits.instructions.contains("\"omitted\""))
    }

    /// A check of the page ("compare my notes with this answer key") proposes the corrections as changes in the same
    /// reply — not a list in the chat waiting for "now fix them" (ISSUE-254).
    @Test func aCheckOfThePageProposesItsCorrections() {
        let instructions = AIPageEdits.instructions
        #expect(instructions.contains("proofread"))
        #expect(instructions.contains("compare"))
        #expect(instructions.contains("never only list corrections"))
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
