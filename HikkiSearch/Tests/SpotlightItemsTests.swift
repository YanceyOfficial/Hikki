import CoreSpotlight
import Foundation
import Testing

@testable import HikkiSearch

struct SpotlightItemsTests {
    @Test func aPageBecomesASearchableItemWithItsTextHeadingsAndTime() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let document = SearchDocument(
            id: "p1", title: "Roadmap", headings: ["Q4", "Risks"], text: "The roadmap is due Friday.\nMore text.", updatedAt: t0)
        let item = SpotlightItems.item(for: document, untitled: "Untitled")
        #expect(item.uniqueIdentifier == "p1")
        #expect(item.domainIdentifier == "pages")
        #expect(item.expirationDate == .distantFuture)
        #expect(item.attributeSet.title == "Roadmap")
        #expect(item.attributeSet.textContent == "The roadmap is due Friday.\nMore text.")
        #expect(item.attributeSet.contentDescription == "The roadmap is due Friday. More text.")
        #expect(item.attributeSet.keywords == ["Q4", "Risks"])
        #expect(item.attributeSet.contentModificationDate == t0)
    }

    @Test func untitledEmptyAndLongPagesAreHandled() {
        let empty = SpotlightItems.item(for: SearchDocument(id: "e", title: "", updatedAt: .now), untitled: "Untitled")
        #expect(empty.attributeSet.title == "Untitled")
        #expect(empty.attributeSet.contentDescription == nil)
        #expect(empty.attributeSet.keywords == nil)
        let long = SearchDocument(
            id: "l", title: "Long", text: String(repeating: "word ", count: SpotlightItems.maxTextCharacters), updatedAt: .now)
        let item = SpotlightItems.item(for: long, untitled: "Untitled")
        #expect(item.attributeSet.textContent?.count == SpotlightItems.maxTextCharacters)
        let description = item.attributeSet.contentDescription ?? ""
        #expect(description.hasSuffix("…") && description.count <= SpotlightItems.descriptionCharacters + 1)
    }

    @Test func onlyTheRealDataFolderWritesToSpotlight() {
        #expect(SpotlightItems.writesAllowed(environment: [:]))
        #expect(SpotlightItems.writesAllowed(environment: ["HIKKI_DATA_DIR": ""]))
        #expect(!SpotlightItems.writesAllowed(environment: ["HIKKI_DATA_DIR": "/tmp/uitest"]))
        #expect(SpotlightItems.writesAllowed(environment: ["HIKKI_DATA_DIR": "/tmp/uitest", "HIKKI_SPOTLIGHT": "1"]))
    }
}
