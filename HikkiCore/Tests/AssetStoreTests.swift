import Foundation
import Testing

@testable import HikkiCore

struct AssetStoreTests {
    @Test func savesAndResolvesAssets() throws {
        let store = AssetStore(directory: try makeTempDirectory())
        let url = try store.save(Data([1, 2, 3]), fileExtension: "PNG")
        #expect(url.hasPrefix(AssetStore.urlPrefix))
        let name = String(url.dropFirst(AssetStore.urlPrefix.count))
        #expect(name.hasSuffix(".png"))
        #expect(try Data(contentsOf: #require(store.file(named: name))) == Data([1, 2, 3]))
    }

    @Test func rejectsUnsupportedTypesOversizeAndPathTricks() throws {
        let store = AssetStore(directory: try makeTempDirectory())
        #expect(throws: AssetStore.AssetError.unsupportedType("svg")) { try store.save(Data(), fileExtension: "svg") }
        #expect(throws: AssetStore.AssetError.tooLarge(10)) { try store.save(Data(count: 10), fileExtension: "png", maxBytes: 5) }
        #expect(store.file(named: "../hikki.sqlite") == nil)
        #expect(store.file(named: ".hidden") == nil)
        #expect(store.file(named: "missing.png") == nil)
    }
}
