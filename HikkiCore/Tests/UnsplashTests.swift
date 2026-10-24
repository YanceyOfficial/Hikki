import Foundation
import Testing

@testable import HikkiCore

struct UnsplashTests {
    private let base = URL(string: "https://unsplash.yancey.app")!

    @Test func searchesThroughTheBackendWithATrimmedQuery() {
        let url = UnsplashClient.searchURL(base: base, query: "  kyoto autumn ", page: 2)
        #expect(url.absoluteString == "https://unsplash.yancey.app/api/unsplash/photos?query=kyoto%20autumn&page=2")
    }

    @Test func readsTheBackendsPhotos() throws {
        let body = """
            {"photos":[{"id":"p1","thumb":"https://images.unsplash.com/1?w=400","regular":"https://images.unsplash.com/1?w=1080",
            "full":"https://images.unsplash.com/1","cover":"https://images.unsplash.com/1?w=2560&q=85&fm=jpg&fit=max",
            "color":"#a0b1c2","alt":null,"author":"Ann",
            "authorUrl":"https://unsplash.com/@ann?utm_source=hikki&utm_medium=referral",
            "photoUrl":"https://unsplash.com/photos/p1?utm_source=hikki&utm_medium=referral",
            "downloadLocation":"https://api.unsplash.com/photos/p1/download"}],"totalPages":3}
            """
        let photos = try UnsplashClient.photos(from: Data(body.utf8), status: 200)
        #expect(photos.map(\.id) == ["p1"])
        #expect(photos[0].author == "Ann")
        #expect(photos[0].alt == nil)
        #expect(photos[0].regular.absoluteString == "https://images.unsplash.com/1?w=1080")
        #expect(photos[0].coverURL.absoluteString == "https://images.unsplash.com/1?w=2560&q=85&fm=jpg&fit=max")
    }

    @Test func anOlderBackendsPhotoWithoutACoverFallsBackToRegular() throws {
        let body = """
            {"photos":[{"id":"p1","thumb":"https://images.unsplash.com/1?w=400","regular":"https://images.unsplash.com/1?w=1080",
            "full":"https://images.unsplash.com/1","color":null,"alt":null,"author":"Ann",
            "authorUrl":"https://unsplash.com/@ann","photoUrl":"https://unsplash.com/photos/p1",
            "downloadLocation":"https://api.unsplash.com/photos/p1/download"}],"totalPages":null}
            """
        let photos = try UnsplashClient.photos(from: Data(body.utf8), status: 200)
        #expect(photos[0].cover == nil)
        #expect(photos[0].coverURL.absoluteString == "https://images.unsplash.com/1?w=1080")
    }

    @Test func aFailureCarriesTheBackendsCode() {
        let limited = Data(#"{"error":{"code":7006,"id":"rateLimited","message":"…"},"requestId":"r"}"#.utf8)
        #expect(throws: UnsplashClient.Failure(code: .rateLimited, status: 429)) {
            try UnsplashClient.photos(from: limited, status: 429)
        }
        let unset = Data(#"{"error":{"code":7101,"id":"unsplashNotConfigured","message":"…"},"requestId":"r"}"#.utf8)
        #expect(throws: UnsplashClient.Failure(code: .unsplashNotConfigured, status: 503)) {
            try UnsplashClient.photos(from: unset, status: 503)
        }
        // An older backend's 403 for the hourly limit; a body that says nothing.
        #expect(throws: UnsplashClient.Failure(code: .rateLimited, status: 403)) {
            try UnsplashClient.photos(from: Data(), status: 403)
        }
        #expect(throws: UnsplashClient.Failure(code: .upstreamFailed, status: 500)) {
            try UnsplashClient.photos(from: Data("oops".utf8), status: 500)
        }
    }
}
