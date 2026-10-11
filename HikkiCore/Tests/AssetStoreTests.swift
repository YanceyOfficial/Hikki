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

    @Test func kindsByExtension() {
        #expect(AssetStore.kind(ofExtension: "JPG") == .image)
        #expect(AssetStore.kind(ofExtension: "mov") == .video)
        #expect(AssetStore.kind(ofExtension: "m4a") == .audio)
        #expect(AssetStore.kind(ofExtension: "pdf") == .file)
        #expect(AssetStore.kind(ofExtension: "") == nil)
        #expect(AssetStore.kind(ofExtension: "a/b") == nil)
        #expect(AssetStore.kind(ofExtension: "averyverylongext") == nil)
    }

    @Test func workspaceFolderTakesNewAssetsAndOldOnesAreCopiedNotMoved() throws {
        let legacy = try makeTempDirectory()
        let store = AssetStore(directory: legacy)
        let old = try store.save(Data([1]), fileExtension: "png")
        let oldName = try #require(AssetStore.name(fromURL: old))

        let workspace = try makeTempDirectory()
        store.useWorkspaceFolder(workspace)
        store.copyLegacyAssets()
        #expect(FileManager.default.fileExists(atPath: workspace.appending(path: "assets/\(oldName)").path))
        #expect(FileManager.default.fileExists(atPath: legacy.appending(path: oldName).path))  // nothing deleted
        let new = try store.save(Data([2]), fileExtension: "png")
        let newName = try #require(AssetStore.name(fromURL: new))
        #expect(store.file(named: newName)?.deletingLastPathComponent().lastPathComponent == "assets")
        #expect(store.file(named: oldName) != nil)
    }

    @Test func chunkedUploadsLandInTheStore() throws {
        let store = AssetStore(directory: try makeTempDirectory())
        let uploads = AssetUploads(store: store, temporary: try makeTempDirectory())
        let id = try uploads.begin(fileExtension: "mp4", size: 6)
        try uploads.append(id, Data([1, 2, 3]))
        try uploads.append(id, Data([4, 5, 6]))
        let url = try uploads.finish(id)
        let name = try #require(AssetStore.name(fromURL: url))
        let file = try #require(store.file(named: name))
        #expect(try Data(contentsOf: file) == Data([1, 2, 3, 4, 5, 6]))
        #expect(file.pathExtension == "mp4")
    }

    @Test func uploadsRefuseMoreThanDeclaredAndUnknownIDs() throws {
        let temp = try makeTempDirectory()
        let uploads = AssetUploads(store: AssetStore(directory: try makeTempDirectory()), temporary: temp)
        let id = try uploads.begin(fileExtension: "pdf", size: 2)
        #expect(throws: AssetUploads.UploadError.tooLarge) { try uploads.append(id, Data([1, 2, 3])) }
        #expect(throws: AssetUploads.UploadError.unknownUpload) { try uploads.finish(id) }  // discarded
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.path).isEmpty)
        #expect(throws: AssetStore.AssetError.unsupportedType("a/b")) { try uploads.begin(fileExtension: "a/b", size: 1) }
        #expect(throws: AssetStore.AssetError.tooLarge(Int.max)) { try uploads.begin(fileExtension: "png", size: Int.max) }
    }

    @Test func cancelledUploadsLeaveNothingBehind() throws {
        let temp = try makeTempDirectory()
        let uploads = AssetUploads(store: AssetStore(directory: try makeTempDirectory()), temporary: temp)
        let id = try uploads.begin(fileExtension: "zip", size: 10)
        try uploads.append(id, Data([1]))
        uploads.cancel(id)
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.path).isEmpty)
    }
}

struct ByteRangeTests {
    @Test func parsesTheFormsMediaElementsSend() {
        #expect(ByteRange.parse(nil, size: 100) == 0..<100)
        #expect(ByteRange.parse("bytes=0-1", size: 100) == 0..<2)
        #expect(ByteRange.parse("bytes=10-", size: 100) == 10..<100)
        #expect(ByteRange.parse("bytes=-30", size: 100) == 70..<100)
        #expect(ByteRange.parse("bytes=90-500", size: 100) == 90..<100)
        #expect(ByteRange.parse("bytes=0-1, 5-6", size: 100) == 0..<2)
    }

    @Test func unusableRangesFallBackToTheWholeFile() {
        #expect(ByteRange.parse("bytes=200-300", size: 100) == 0..<100)
        #expect(ByteRange.parse("bytes=5-1", size: 100) == 0..<100)
        #expect(ByteRange.parse("items=0-1", size: 100) == 0..<100)
        #expect(ByteRange.parse("bytes=x-y", size: 100) == 0..<100)
        #expect(ByteRange.parse("bytes=0-1", size: 0) == 0..<0)
    }
}
