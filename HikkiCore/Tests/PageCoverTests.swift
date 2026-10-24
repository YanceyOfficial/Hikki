import Foundation
import Testing

@testable import HikkiCore

struct PageCoverTests {
    @Test func gradientsAndPicturesReadAsTheEditorStoresThem() {
        #expect(PageCover("gradient:ocean") == .gradient("ocean"))
        #expect(PageCover("hikki-editor://assets/a1.png") == .image(url: "hikki-editor://assets/a1.png", position: 50))
        #expect(PageCover("https://images.unsplash.com/photo-1?w=2400#y=35") == .image(url: "https://images.unsplash.com/photo-1?w=2400", position: 35))
        #expect(PageCover("https://example.com/a.jpg#y=0") == .image(url: "https://example.com/a.jpg", position: 0))
        #expect(PageCover("https://example.com/a.jpg#y=250") == .image(url: "https://example.com/a.jpg", position: 100))
    }

    @Test func somethingElseIsNoCover() {
        #expect(PageCover(nil) == nil)
        #expect(PageCover("") == nil)
        #expect(PageCover("gradient:") == nil)
        #expect(PageCover("javascript:alert(1)") == nil)
        #expect(PageCover("file:///etc/passwd") == nil)
        // Not our fragment: kept as part of the URL.
        #expect(PageCover("https://example.com/a.jpg#y=-5") == .image(url: "https://example.com/a.jpg#y=-5", position: 50))
    }

    @Test func picturesSayWhereTheyLoadFrom() {
        #expect(PageCover("hikki-editor://assets/a1.png#y=20")?.assetName == "a1.png")
        #expect(PageCover("hikki-editor://assets/a1.png")?.webURL == nil)
        #expect(PageCover("https://example.com/a.jpg#y=20")?.webURL == URL(string: "https://example.com/a.jpg"))
        #expect(PageCover("https://example.com/a.jpg")?.assetName == nil)
        #expect(PageCover("gradient:ocean")?.webURL == nil)
        #expect(PageCover("blob:hikki-editor://x")?.webURL == nil)
    }
}
