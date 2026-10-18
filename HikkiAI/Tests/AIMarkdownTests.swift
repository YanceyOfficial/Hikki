import Foundation
import Testing

@testable import HikkiAI

struct AIMarkdownTests {
    private func links(_ text: String) -> [String] {
        AIMarkdown.attributed(text).runs.compactMap { $0.link?.absoluteString }
    }

    private func text(_ string: AttributedString) -> String { String(string.characters) }

    /// Every link left anywhere in the blocks (lists, quotes, tables included).
    private func allLinks(_ blocks: [AIMarkdown.Block]) -> [String] {
        func links(_ string: AttributedString) -> [String] { string.runs.compactMap { $0.link?.absoluteString } }
        return blocks.flatMap { block -> [String] in
            switch block {
            case .paragraph(let text), .heading(_, let text): links(text)
            case .list(let list): list.items.flatMap { allLinks($0.blocks) }
            case .quote(let blocks): allLinks(blocks)
            case .table(let table): (table.header + table.rows.flatMap { $0 }).flatMap(links)
            case .code, .rule: []
            }
        }
    }

    @Test func keepsWebLinksAndStyles() {
        let styled = AIMarkdown.attributed("See **this** [page](https://example.com/a).")
        #expect(String(styled.characters) == "See this page.")
        #expect(
            links("See [page](https://example.com/a) or [http](http://example.com)") == ["https://example.com/a", "http://example.com"])
    }

    @Test func dropsEveryOtherSchemeButKeepsTheText() {
        let text = "[open](hikki://page/x) [call](tel:123) [js](javascript:alert(1)) [file](file:///etc/hosts) [app](shortcuts://run)"
        #expect(links(text).isEmpty)
        #expect(String(AIMarkdown.attributed(text).characters) == "open call js file app")
        // Bare autolinks too.
        #expect(links("<mailto:a@b.c> <sms:123>").isEmpty)
    }

    @Test func splitsAnAnswerIntoParagraphsAndLists() {
        let blocks = AIMarkdown.blocks(
            "Two things are open:\n\n- **Submit** on Wednesday.\n- Publish the site\n\n1. First\n2. Second\n\nStill open,\nas written.")
        guard blocks.count == 4, case .paragraph(let intro) = blocks[0], case .list(let bullets) = blocks[1],
            case .list(let numbers) = blocks[2], case .paragraph(let last) = blocks[3]
        else {
            Issue.record("unexpected blocks: \(blocks)")
            return
        }
        #expect(text(intro) == "Two things are open:")
        #expect(!bullets.ordered && bullets.items.count == 2)
        #expect(numbers.ordered && numbers.start == 1 && numbers.items.count == 2)
        // A line break inside a paragraph stays, as written.
        #expect(text(last) == "Still open,\nas written.")
        // Not list markers: a dash with no space, a year, a long number inside a paragraph.
        #expect(AIMarkdown.blocks("-x\n2026.\n1234. y").count == 1)
    }

    @Test func readsHeadingsNestedListsQuotesAndRules() {
        let blocks = AIMarkdown.blocks(
            """
            ## Plan
            3. Three
               - nested *one*
               - [x] done
            > quoted **text**
            > - in a quote

            ---
            """)
        guard blocks.count == 4, case .heading(2, let title) = blocks[0], case .list(let list) = blocks[1],
            case .quote(let quoted) = blocks[2], blocks[3] == .rule
        else {
            Issue.record("unexpected blocks: \(blocks)")
            return
        }
        #expect(text(title) == "Plan")
        #expect(list.ordered && list.start == 3)
        guard case .list(let nested) = list.items[0].blocks.last else {
            Issue.record("no nested list")
            return
        }
        #expect(!nested.ordered && nested.items.map(\.checked) == [nil, true])
        #expect(quoted.count == 2)
    }

    @Test func keepsInlineCodeAndFencedCode() {
        let blocks = AIMarkdown.blocks("Call `run()` now.\n\n```swift\nlet a = 1\n  print(a)\n```\n\n```\nplain\n```")
        guard blocks.count == 3, case .paragraph(let line) = blocks[0] else {
            Issue.record("unexpected blocks: \(blocks)")
            return
        }
        #expect(line.runs.contains { $0.inlinePresentationIntent == .code && String(line[$0.range].characters) == "run()" })
        #expect(blocks[1] == .code(language: "swift", code: "let a = 1\n  print(a)"))
        #expect(blocks[2] == .code(language: nil, code: "plain"))
    }

    @Test func readsTables() {
        let blocks = AIMarkdown.blocks("| Name | Size |\n|:-----|-----:|\n| **a** | 1 |\n| [b](tel:1) | 2 |")
        guard case .table(let table) = blocks.first else {
            Issue.record("no table: \(blocks)")
            return
        }
        #expect(table.alignments == [.leading, .trailing])
        #expect(table.header.map(text) == ["Name", "Size"])
        #expect(table.rows.map { $0.map(text) } == [["a", "1"], ["b", "2"]])
        #expect(allLinks(blocks).isEmpty)
    }

    @Test func keepsOnlyWebLinksEverywhere() {
        let blocks = AIMarkdown.blocks(
            """
            - [a](https://example.com) [b](hikki://page/x)
            > [c](tel:123) see https://example.org/x.
            > ![pic](https://example.com/p.png) ![local](file:///etc/x.png)

            | [d](javascript:alert(1)) | <sms:1> |
            |---|---|
            | www.example.net | [e](http://example.com) |
            """)
        #expect(
            allLinks(blocks) == [
                "https://example.com", "https://example.org/x", "https://example.com/p.png", "http://www.example.net",
                "http://example.com",
            ])
    }

    @Test func copesWithHalfWrittenMarkdown() {
        // An unclosed fence is code to the end, while it streams.
        #expect(
            AIMarkdown.blocks("Here:\n\n```python\nprint(1)\nfor") == [
                .paragraph(AttributedString("Here:")), .code(language: "python", code: "print(1)\nfor"),
            ])
        // A fence still being typed shows nothing rather than stray backticks.
        #expect(AIMarkdown.blocks("Here:\n``") == [.paragraph(AttributedString("Here:"))])
        #expect(AIMarkdown.blocks("Here:\n\n```") == [.paragraph(AttributedString("Here:"))])
        // Every prefix of an answer parses (no crash, no empty paragraphs).
        let answer = "# T\n\n| a | b |\n|---|---|\n| 1 | **2** |\n\n> - x\n>   1. y\n\n```js\nlet a = `x`\n```\n[l](https://e.com)"
        for end in answer.indices {
            for block in AIMarkdown.blocks(String(answer[..<end])) {
                if case .paragraph(let text) = block { #expect(!text.characters.isEmpty) }
            }
        }
    }

    @Test func singleTildesAreNotStrikethrough() {
        guard case .paragraph(let line) = AIMarkdown.blocks("About ~5 min, ~~gone~~, `a~b`").first else {
            Issue.record("no paragraph")
            return
        }
        #expect(text(line) == "About ~5 min, gone, a~b")
        #expect(line.runs.filter { $0.inlinePresentationIntent?.contains(.strikethrough) == true }.count == 1)
        // Fenced code keeps its tildes untouched.
        #expect(AIMarkdown.blocks("~~~\na ~ b\n~~~") == [.code(language: nil, code: "a ~ b")])
        #expect(AIMarkdown.escapingLoneTildes("<https://e.com/~me>") == "<https://e.com/~me>")
    }
}
