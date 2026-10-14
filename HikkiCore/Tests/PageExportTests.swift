import Foundation
import Testing

@testable import HikkiCore

struct PageExportTests {
    @Test func fileNamesComeFromTheTitleWithoutPathTricks() {
        #expect(PageExport.fileName(for: "Trip / Plan: 2026", fallback: "Untitled") == "Trip - Plan- 2026")
        #expect(PageExport.fileName(for: "  ..hidden", fallback: "Untitled") == "hidden")
        #expect(PageExport.fileName(for: "   ", fallback: "Untitled") == "Untitled")
        #expect(PageExport.fileName(for: String(repeating: "a", count: 300), fallback: "x").count == 120)
    }

    @Test func attachmentLinksBecomeRelativeAndAreListedOnce() {
        let html =
            #"<img src="hikki-editor://assets/a1.png"><a href="hikki-editor://assets/doc-2.pdf">x</a><img src="hikki-editor://assets/a1.png">"#
        let (text, assets) = PageExport.relinkAssets(in: html)
        #expect(text == #"<img src="assets/a1.png"><a href="assets/doc-2.pdf">x</a><img src="assets/a1.png">"#)
        #expect(assets == ["a1.png", "doc-2.pdf"])
        #expect(PageExport.relinkAssets(in: "no attachments").assets.isEmpty)
    }

    @Test func aPageWithoutAttachmentsIsOneFile() throws {
        let wrapper = PageExport.package(document: Data("# Hi\n".utf8), name: "Hi", fileExtension: "md", assets: [])
        #expect(wrapper.isRegularFile)
        #expect(wrapper.preferredFilename == "Hi.md")
        #expect(wrapper.regularFileContents == Data("# Hi\n".utf8))
    }

    @Test func attachmentsMakeAFolderWithAnAssetsFolder() throws {
        let folder = try makeTempDirectory()
        let image = folder.appending(path: "a1.png")
        try Data([1, 2, 3]).write(to: image)
        let wrapper = PageExport.package(
            document: Data("doc".utf8), name: "Trip", fileExtension: "html",
            assets: [("a1.png", image), ("missing.png", folder.appending(path: "missing.png"))])
        #expect(wrapper.isDirectory && wrapper.preferredFilename == "Trip")
        let children = try #require(wrapper.fileWrappers)
        #expect(children["Trip.html"]?.regularFileContents == Data("doc".utf8))
        #expect(children["assets"]?.fileWrappers?.keys.sorted() == ["a1.png"])
        // Written out, it is the folder a user gets.
        let out = folder.appending(path: "out")
        try wrapper.write(to: out, options: [], originalContentsURL: nil)
        #expect(FileManager.default.fileExists(atPath: out.appending(path: "assets/a1.png").path))
    }

    @Test func jsonIsThePageFileAsStored() throws {
        let store = try DocumentStore.inMemory()
        let record = try store.create(id: "p", now: Date(timeIntervalSince1970: 1_760_000_000))
        let page = try PageFiles.decode(try PageExport.json(record))
        #expect(page.id == "p" && page.format == PageFile.currentFormat)
    }
}
