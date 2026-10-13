import Foundation
import Testing

@testable import HikkiCore

struct EditorNavigationPolicyTests {
    private func decide(_ url: String, isMainFrame: Bool?, isLinkClick: Bool = false) -> NavigationDecision {
        EditorNavigationPolicy.decide(
            url: URL(string: url), isMainFrame: isMainFrame, isLinkClick: isLinkClick, editorScheme: "hikki-editor")
    }

    @Test func theBundledEditorLoadsOnlyAsThePage() {
        #expect(decide("hikki-editor://app/index.html", isMainFrame: true) == .load)
        // An uploaded HTML file must never become the page.
        #expect(decide("hikki-editor://assets/x.html", isMainFrame: true) == .cancel)
        // An embed's frame must not load the editor beside itself (same origin as the page).
        #expect(decide("hikki-editor://app/index.html", isMainFrame: false) == .cancel)
        #expect(decide("hikki-editor://app/index.html", isMainFrame: nil) == .cancel)
    }

    @Test func framesShowHttpsPagesAndSnippetsOnly() {
        #expect(decide("https://www.youtube-nocookie.com/embed/x", isMainFrame: false) == .load)
        #expect(decide("about:srcdoc", isMainFrame: false) == .load)
        #expect(decide("http://example.com/", isMainFrame: false) == .cancel)
        #expect(decide("data:text/html,hi", isMainFrame: false) == .cancel)
        #expect(decide("file:///etc/passwd", isMainFrame: false) == .cancel)
        // The page itself never leaves the editor.
        #expect(decide("https://example.com/", isMainFrame: true) == .cancel)
    }

    @Test func clickedLinksGoToTheSystem() {
        #expect(decide("https://example.com/", isMainFrame: true, isLinkClick: true) == .openOutside)
        #expect(decide("mailto:someone@example.com", isMainFrame: true, isLinkClick: true) == .openOutside)
        #expect(decide("https://example.com/", isMainFrame: nil, isLinkClick: true) == .openOutside)
        #expect(decide("https://example.com/", isMainFrame: true, isLinkClick: false) == .cancel)
        #expect(EditorNavigationPolicy.decide(url: nil, isMainFrame: true, isLinkClick: true, editorScheme: "hikki-editor") == .cancel)
    }
}
