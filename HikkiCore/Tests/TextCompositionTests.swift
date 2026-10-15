#if canImport(AppKit)
    import AppKit
    import Testing

    @testable import HikkiCore

    @MainActor
    struct TextCompositionTests {
        @Test func markedTextMeansTheInputMethodHasTheKeys() {
            let field = NSTextView()
            #expect(!TextComposition.isComposing(field))
            // An IME showing 綺麗 as a candidate, not yet committed.
            field.setMarkedText(
                "きれい", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(TextComposition.isComposing(field))
            field.unmarkText()
            #expect(!TextComposition.isComposing(field))
            #expect(!TextComposition.isComposing(nil))
        }
    }
#endif
