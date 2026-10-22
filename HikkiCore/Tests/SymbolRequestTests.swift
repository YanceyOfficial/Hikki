import Foundation
import Testing

@testable import HikkiCore

struct SymbolRequestTests {
    @Test func aSymbolNameAndSizeAreRead() {
        let request = SymbolRequest.parse(URL(string: "hikki-editor://sf/doc.on.clipboard.png?pt=20")!)
        #expect(request == SymbolRequest(name: "doc.on.clipboard", points: 20))
        #expect(SymbolRequest.parse(URL(string: "hikki-editor://sf/photo.png")!)?.points == 17)
        #expect(SymbolRequest.parse(URL(string: "hikki-editor://sf/photo.png?pt=400")!)?.points == 96)
        #expect(SymbolRequest.parse(URL(string: "hikki-editor://sf/photo.png?pt=1")!)?.points == 8)
        // Whole points only, and nothing a number can't be: the sizes drawn stay a bounded set.
        #expect(SymbolRequest.parse(URL(string: "hikki-editor://sf/photo.png?pt=20.6")!)?.points == 21)
        for odd in ["nan", "inf", "-inf", "1e400", "x"] {
            #expect(SymbolRequest.parse(URL(string: "hikki-editor://sf/photo.png?pt=\(odd)")!)?.points == 17, Comment(rawValue: odd))
        }
    }

    @Test func onlySymbolNamesGetThrough() {
        for bad in [
            "hikki-editor://app/index.html", "hikki-editor://sf/photo.svg", "hikki-editor://sf/a/photo.png",
            "hikki-editor://sf/..png", "hikki-editor://sf/photo%20x.png", "hikki-editor://sf/.png",
            "hikki-editor://sf/Photo-Badge.png", "hikki-editor://assets/photo.png",
        ] {
            #expect(SymbolRequest.parse(URL(string: bad)!) == nil, Comment(rawValue: bad))
        }
    }
}
