import CoreSpotlight
import Foundation
import Testing

@testable import HikkiSearch

struct SpotlightItemsTests {
    @Test func aPageBecomesASearchableItemWithItsTextHeadingsAndTime() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let document = SearchDocument(
            id: "p1", title: "Roadmap",
            blocks: [
                SearchBlock(id: "h1", isHeading: true, text: "Q4"), SearchBlock(id: "p1", text: "The roadmap is due Friday."),
                SearchBlock(id: "h2", isHeading: true, text: "Risks"), SearchBlock(id: "p2", text: "More text."),
            ], updatedAt: t0)
        let item = SpotlightItems.item(for: document, untitled: "Untitled")
        #expect(item.uniqueIdentifier == "p1")
        #expect(item.domainIdentifier == "pages")
        #expect(item.expirationDate == .distantFuture)
        #expect(item.attributeSet.title == "Roadmap")
        #expect(item.attributeSet.textContent == "Q4\nThe roadmap is due Friday.\nRisks\nMore text.")
        #expect(item.attributeSet.contentDescription == "Q4 The roadmap is due Friday. Risks More text.")
        #expect(item.attributeSet.displayName == "Roadmap")
        #expect(item.attributeSet.keywords == ["Roadmap", "Q4", "Risks"])
        #expect(item.attributeSet.contentModificationDate == t0)
    }

    @Test func untitledEmptyAndLongPagesAreHandled() {
        let empty = SpotlightItems.item(for: SearchDocument(id: "e", title: "", updatedAt: .now), untitled: "Untitled")
        #expect(empty.attributeSet.title == "Untitled")
        #expect(empty.attributeSet.contentDescription == nil)
        #expect(empty.attributeSet.displayName == "Untitled")
        #expect(empty.attributeSet.keywords == ["Untitled"])
        let long = SearchDocument(
            id: "l", title: "Long",
            blocks: [SearchBlock(id: "", text: String(repeating: "word ", count: SpotlightItems.maxTextCharacters))],
            updatedAt: .now)
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
