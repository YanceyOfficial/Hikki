import CoreSpotlight
import Foundation

/// What a page looks like in the device's Spotlight index (Core Spotlight): its title, its text to search, its
/// headings as keywords, the edited time. The system ranks and shows these — with its own semantic matching
/// where that exists — and hands the page's id back when one is picked. Private to the device.
public enum SpotlightItems {
    /// The domain every page item is filed under (so they can all be removed at once).
    public static let domain = "pages"
    /// How much page text Spotlight gets to search.
    public static let maxTextCharacters = 50_000
    /// How much of it shows under the title.
    static let descriptionCharacters = 200

    public static func item(for document: SearchDocument, untitled: String) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = document.title.isEmpty ? untitled : document.title
        attributes.textContent = String(document.text.prefix(maxTextCharacters))
        attributes.contentDescription = description(of: document.text)
        attributes.keywords = document.headings.isEmpty ? nil : document.headings
        attributes.contentModificationDate = document.updatedAt
        let item = CSSearchableItem(uniqueIdentifier: document.id, domainIdentifier: domain, attributeSet: attributes)
        item.expirationDate = .distantFuture
        return item
    }

    /// The first words of the text on one line, nil when there are none.
    static func description(of text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        var out = ""
        for word in words {
            if out.count + word.count + 1 > descriptionCharacters { return out + "…" }
            out += out.isEmpty ? String(word) : " " + word
        }
        return out
    }
}
