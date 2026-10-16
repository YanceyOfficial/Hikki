import Foundation
import Testing

@testable import HikkiAI

struct AIMarkdownTests {
    private func links(_ text: String) -> [String] {
        AIMarkdown.attributed(text).runs.compactMap { $0.link?.absoluteString }
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

    @Test func splitsAnAnswerIntoParagraphsAndListItems() {
        let blocks = AIMarkdown.blocks(
            "Two things are open:\n\n- **Submit** on Wednesday.\n* Publish the site\n\n1. First\n12. Twelfth\nStill open,\nas written.")
        #expect(blocks.map(\.kind) == [.paragraph, .bullet, .bullet, .numbered("1."), .numbered("12."), .paragraph])
        #expect(
            blocks.map { String($0.text.characters) } == [
                "Two things are open:", "Submit on Wednesday.", "Publish the site", "First", "Twelfth", "Still open,\nas written.",
            ])
        // Not list markers: a dash with no space, a year, a long number.
        #expect(AIMarkdown.blocks("-x\n2026.\n1234. y").map(\.kind) == [.paragraph])
    }

    @Test func listItemsKeepOnlyWebLinks() {
        let item = AIMarkdown.blocks("- [a](https://example.com) [b](hikki://page/x)")[0]
        #expect(item.text.runs.compactMap { $0.link?.absoluteString } == ["https://example.com"])
    }
}
