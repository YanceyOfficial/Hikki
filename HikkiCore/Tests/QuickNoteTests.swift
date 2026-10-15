import Foundation
import Testing

@testable import HikkiCore

struct QuickNoteTests {
    @Test func theClipboardsFirstLineIsTheTitleTheRestTheBody() {
        let note = QuickNote.fromClipboard("\n  Trip ideas  \nKyoto in spring\n\nNara deer\n\n")
        #expect(note == QuickNote(title: "Trip ideas", lines: ["Kyoto in spring", "", "Nara deer"]))
        #expect(note?.text == "Kyoto in spring\n\nNara deer")
    }

    @Test func aLinkAloneIsTitledByItsSite() {
        #expect(
            QuickNote.fromClipboard("https://www.example.com/a/b?c=1")
                == QuickNote(title: "example.com", lines: ["https://www.example.com/a/b?c=1"]))
        // A link with more text after it is just a first line.
        #expect(QuickNote.fromClipboard("https://example.com\nnotes")?.title == "https://example.com")
    }

    @Test func aLongFirstLineStaysInTheBody() {
        let long = String(repeating: "あ", count: 100)
        let note = QuickNote.fromClipboard(long)
        #expect(note?.title.count == 81)
        #expect(note?.title.hasSuffix("…") == true)
        #expect(note?.lines == [long])
    }

    @Test func blanksMakeNoNote() {
        #expect(QuickNote.fromClipboard("") == nil)
        #expect(QuickNote.fromClipboard("  \n \n") == nil)
    }

    @Test func theBodyIsAParagraphPerLine() {
        let content = QuickNote(title: "T", lines: ["a", ""]).content
        guard case .object(let doc) = content, case .array(let paragraphs)? = doc["content"] else {
            return #expect(Bool(false))
        }
        #expect(paragraphs.count == 2)
        // No lines: one empty paragraph, as a new page has.
        guard case .object(let empty) = QuickNote(title: "T", lines: []).content, case .array(let one)? = empty["content"]
        else { return #expect(Bool(false)) }
        #expect(one.count == 1)
    }
}
