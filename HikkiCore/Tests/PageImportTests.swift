import Foundation
import Testing
import UniformTypeIdentifiers

@testable import HikkiCore

struct PageImportTests {
    /// A folder like an export: `Trip.md`, `assets/a b.png`, and a file outside it.
    private func fixture() throws -> (root: URL, folder: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "import-\(UUID().uuidString)")
        let folder = root.appending(path: "Trip")
        try FileManager.default.createDirectory(at: folder.appending(path: "assets"), withIntermediateDirectories: true)
        try Data("# Trip".utf8).write(to: folder.appending(path: "Trip.md"))
        try Data("notes".utf8).write(to: folder.appending(path: "b.txt"))
        try Data([1, 2, 3]).write(to: folder.appending(path: "assets/a b.png"))
        try Data([9]).write(to: root.appending(path: "secret.png"))
        return (root, folder)
    }

    @Test func aFolderListsItsDocuments() throws {
        let (root, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(PageImport.documents(in: folder).map(\.lastPathComponent) == ["b.txt", "Trip.md"])
    }

    @Test func onlyFilesInsideTheFolderCount() throws {
        let (root, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(PageImport.localFile("assets/a%20b.png", base: folder)?.lastPathComponent == "a b.png")
        #expect(PageImport.localFile("./assets/a b.png", base: folder) != nil)
        #expect(PageImport.localFile("../secret.png", base: folder) == nil)
        #expect(PageImport.localFile("assets/../../secret.png", base: folder) == nil)
        #expect(PageImport.localFile(root.appending(path: "secret.png").path, base: folder) == nil)
        #expect(PageImport.localFile("https://example.com/a.png", base: folder) == nil)
        #expect(PageImport.localFile("file:///etc/hosts", base: folder) == nil)
        #expect(PageImport.localFile("assets/missing.png", base: folder) == nil)
        #expect(PageImport.localFile("assets", base: folder) == nil)
    }

    @Test func relativePicturesBecomeAssetsOncePerFile() throws {
        let (root, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let image: (String) -> JSONValue = { src in
            .object(["type": .string("image"), "attrs": .object(["src": .string(src)])])
        }
        let doc: JSONValue = .object([
            "type": .string("doc"),
            "content": .array([
                image("assets/a%20b.png"), image("./assets/a b.png"), image("../secret.png"), image("https://x.example/p.png"),
            ]),
        ])
        var copies = 0
        let (content, copied) = PageImport.relinkLocalFiles(in: doc, base: folder) { _ in
            copies += 1
            return "hikki-editor://assets/new.png"
        }
        #expect(copies == 1 && copied == 1)
        guard case .object(let object) = content, case .array(let nodes) = object["content"] else { return #expect(Bool(false)) }
        let sources = nodes.compactMap { node -> String? in
            guard case .object(let n) = node, case .object(let attrs) = n["attrs"], case .string(let src) = attrs["src"] else { return nil }
            return src
        }
        #expect(sources == ["hikki-editor://assets/new.png", "hikki-editor://assets/new.png", "../secret.png", "https://x.example/p.png"])
    }

    @Test func droppedFilesImportOnlyAsFoldersOrDocuments() throws {
        let (root, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let dropped = [
            folder.appending(path: "Trip.md"), root.appending(path: "secret.png"), folder, folder.appending(path: "b.txt"),
        ]
        #expect(PageImport.importable(dropped).map(\.lastPathComponent) == ["Trip.md", "Trip", "b.txt"])
    }

    @Test func aDroppedItemImportsByItsTypeAndPlainTextNeedsAFileName() {
        #expect(PageImport.documentType(registered: ["net.daringfireball.markdown"], suggestedName: "Trip") != nil)
        #expect(PageImport.documentType(registered: ["public.html"], suggestedName: nil) == .html)
        #expect(PageImport.documentType(registered: ["public.folder"], suggestedName: "Notes") == .folder)
        // A picture or a PDF doesn't import; the first type that does wins.
        #expect(PageImport.documentType(registered: ["public.png"], suggestedName: "a.png") == nil)
        #expect(PageImport.documentType(registered: ["com.adobe.pdf", "public.html"], suggestedName: "x") == .html)
        // Text dragged out of another app is a snippet; a text file has a name.
        #expect(PageImport.documentType(registered: ["public.utf8-plain-text"], suggestedName: nil) == nil)
        #expect(PageImport.documentType(registered: ["public.plain-text"], suggestedName: "notes.txt") == .plainText)
    }

    @Test func aDroppedDocumentKeepsItsNameAndGetsAnExtensionItsFormatIsReadFrom() throws {
        let markdown = try #require(UTType("net.daringfireball.markdown"))
        #expect(PageImport.fileName(suggestedName: "Trip.md", type: markdown) == "Trip.md")
        #expect(PageImport.fileName(suggestedName: "Trip", type: markdown).hasPrefix("Trip."))
        #expect(
            ImportFormat(fileExtension: (PageImport.fileName(suggestedName: "Trip", type: markdown) as NSString).pathExtension) == .markdown
        )
        #expect(PageImport.fileName(suggestedName: "Page", type: .html) == "Page.html")
        #expect(PageImport.fileName(suggestedName: nil, type: .plainText) == "Untitled.txt")
        #expect(PageImport.fileName(suggestedName: "Notes", type: .folder) == "Notes")
        // The drag source names the file: it never reaches outside the folder the copy is made in.
        #expect(PageImport.fileName(suggestedName: "../../Library/x.md", type: markdown) == "x.md")
        #expect(PageImport.fileName(suggestedName: "..", type: .folder) == "Untitled")
        #expect(PageImport.fileName(suggestedName: "a/", type: .html) == "a.html")
        #expect(!PageImport.fileName(suggestedName: "../..", type: .html).contains("/"))
    }
}
