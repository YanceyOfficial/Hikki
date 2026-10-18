import Foundation
import Testing

@testable import HikkiAI

/// Tuist copies HighlightSwift's resource bundle into the test bundle, a place its `Bundle.module` accessor only finds
/// through this override — set before anything reads it (both lookups are made once).
private let resources: Void = {
    final class Marker {}
    setenv("PACKAGE_RESOURCE_BUNDLE_PATH", Bundle(for: Marker.self).resourcePath ?? "", 1)
}()

struct CodeHighlighterTests {
    init() { _ = resources }

    @Test func findsHighlightJS() {
        #expect(CodeHighlighter.resourcesFound)
    }

    private func tokens(_ highlight: CodeHighlight, in code: String) -> [(String, CodeToken)] {
        let chars = Array(code)
        return highlight.spans.map { (String(chars[$0.range]), $0.token) }
    }

    @Test func coloursCodeByToken() async throws {
        let code = "  // note\nlet name = \"Hikki\"\nreturn 42"
        let highlight = try #require(await CodeHighlighter.shared.highlight(code, language: "swift"))
        let found = tokens(highlight, in: code)
        // Ranges count from the code's own start, leading spaces included.
        #expect(found.contains { $0.0 == "// note" && $0.1 == .comment })
        #expect(found.contains { $0.0 == "let" && $0.1 == .keyword })
        #expect(found.contains { $0.0 == "\"Hikki\"" && $0.1 == .string })
        #expect(found.contains { $0.0 == "42" && $0.1 == .number })
    }

    @Test func plainTextAndUnknownLanguagesStayPlain() async {
        #expect(await CodeHighlighter.shared.highlight("just words", language: "text") == nil)
        #expect(await CodeHighlighter.shared.highlight("x = 1", language: "no-such-language") == nil)
        #expect(await CodeHighlighter.shared.highlight("   \n", language: nil) == nil)
    }

    @Test func aColouringStillAppliesWhileTheBlockGrows() async throws {
        let highlight = try #require(await CodeHighlighter.shared.highlight("let a = 1", language: "swift"))
        #expect(highlight.applies(to: "let a = 1\nlet b"))
        #expect(!highlight.applies(to: "var a = 1"))
    }
}
