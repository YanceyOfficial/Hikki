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
}
