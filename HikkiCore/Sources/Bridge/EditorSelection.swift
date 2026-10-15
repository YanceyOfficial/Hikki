import Foundation

/// Text selected in a page (the `selection` bridge message): the page it was selected in, and its words.
public struct EditorSelection: Equatable, Sendable {
    public let docId: String
    public let text: String

    public init(docId: String, text: String) {
        self.docId = docId
        self.text = text
    }

    /// The selected words when they belong to `pageID` — Ask AI sends a passage only with a question about its own
    /// page, never with one about the page beside it.
    public func text(in pageID: String?) -> String? {
        pageID == docId ? text : nil
    }
}
