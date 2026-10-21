import Foundation
import Testing

@testable import HikkiCore

struct WorkspaceTransferTests {
    private func summary(_ id: String, _ title: String, parent: String? = nil, sort: Double) -> PageSummary {
        PageSummary(
            id: id, parentId: parent, title: title, icon: nil, updatedAt: Date(timeIntervalSince1970: 0), favoritedAt: nil,
            deletedAt: nil, sortKey: sort)
    }

    // MARK: - Export plan

    @Test func theExportMirrorsTheTree() {
        let pages = [
            summary("b", "Beta", sort: 1),
            summary("a", "Alpha", sort: 0),
            summary("a1", "Day 1", parent: "a", sort: 0),
            summary("a1x", "Notes", parent: "a1", sort: 0),
            summary("orphan", "Lost", parent: "trashed", sort: 2),
        ]
        let entries = WorkspaceExport.plan(pages, fileExtension: "md", fallback: "Untitled")
        #expect(entries.map(\.path) == ["Alpha.md", "Alpha/Day 1.md", "Alpha/Day 1/Notes.md", "Beta.md", "Lost.md"])
        #expect(entries.map(\.depth) == [0, 1, 2, 0, 0])
        // Each one's place among its siblings; a page whose parent is in the trash sits at the top, as in the sidebar.
        #expect(entries.map(\.order) == [0, 0, 0, 1, 2])
        #expect(entries[2].assetPrefix == "../../assets/")
        #expect(entries[0].assetPrefix == "assets/")
    }

    @Test func siblingNamesAreSafeAndUnique() {
        let pages = [
            summary("1", "Plan", sort: 0),
            summary("2", "plan", sort: 1),
            summary("3", "Plan", sort: 2),
            summary("4", "a/b: c", sort: 3),
            summary("5", "", sort: 4),
            summary("6", "", sort: 5),
            summary("7", "Assets", sort: 6),
            summary("8", "Assets", parent: "1", sort: 0),
            summary("9", "Café", parent: "1", sort: 1),
            summary("10", "Cafe\u{301}", parent: "1", sort: 2),
        ]
        let paths = WorkspaceExport.plan(pages, fileExtension: "json", fallback: "Untitled").map(\.path)
        #expect(
            paths == [
                "Plan.json", "Plan/Assets.json", "Plan/Café.json", "Plan/Cafe\u{301} 2.json", "plan 2.json", "Plan 3.json",
                "a-b- c.json", "Untitled.json", "Untitled 2.json", "Assets 2.json",
            ])
    }

    @Test func uniqueNamesNumberFromTwo() {
        var taken: Set<String> = []
        #expect(WorkspaceExport.uniqueName("A", taken: &taken) == "A")
        #expect(WorkspaceExport.uniqueName("a", taken: &taken) == "a 2")
        #expect(WorkspaceExport.uniqueName("A", taken: &taken) == "A 3")
    }

    @Test func exportFoldersDontOverwrite() throws {
        let destination = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let first = try WorkspaceExport.makeFolder(in: destination, workspace: "My/Notes", date: date)
        let second = try WorkspaceExport.makeFolder(in: destination, workspace: "My/Notes", date: date)
        #expect(first.lastPathComponent.hasPrefix("My-Notes 2025-10-"))
        #expect(second.lastPathComponent == first.lastPathComponent + " 2")
    }

    @Test func documentsLinkTheSharedAssetsFolderAndCarryTheirStamp() {
        let entry = WorkspaceExport.Entry(id: "x", path: "A/B.md", depth: 1, order: 2)
        let (data, names) = WorkspaceExport.document(text: "![](hikki-editor://assets/p.png)", entry: entry, format: .markdown)
        #expect(String(decoding: data, as: UTF8.self) == "---\nhikki-id: x\nhikki-order: 2\n---\n\n![](../assets/p.png)")
        #expect(names == ["p.png"])
    }

    @Test func stampsReadBackAndFrontMatterIsNotPageText() {
        let markdown = TransferStamp.stamp("# A\n", id: "p-1", order: 3, format: .markdown)
        #expect(TransferStamp.read(markdown, format: .markdown) == .init(id: "p-1", order: 3))
        #expect(TransferStamp.stripFrontMatter(markdown) == "# A\n")
        let html = TransferStamp.stamp(
            "<!doctype html>\n<html>\n<head>\n<title>A</title>\n</head>\n<body></body></html>", id: "p-1", order: 2, format: .html)
        #expect(html.contains("<head>\n<meta name=\"hikki-id\" content=\"p-1\">"))
        #expect(TransferStamp.read(html, format: .html) == .init(id: "p-1", order: 2))
        // Another app's front matter goes too; a rule opening a document stays; an id that isn't one is dropped.
        #expect(TransferStamp.stripFrontMatter("---\ntags: [a]\n---\nText") == "Text")
        #expect(TransferStamp.stripFrontMatter("---\nText") == "---\nText")
        #expect(TransferStamp.read("---\nhikki-id: ../x\nhikki-order: 1\n---\n", format: .markdown) == .init(order: 1))
        #expect(TransferStamp.read("# A", format: .markdown) == .init())
    }

    // MARK: - Import plan

    /// A folder like a Markdown export plus loose files: `Trip.md` + `Trip/`, a folder with no page, an empty folder,
    /// `assets/`, a picture and a non-page JSON.
    private func importFixture() throws -> URL {
        let root = try makeTempDirectory()
        let fm = FileManager.default
        for folder in ["Trip/Day 1", "Recipes", "Empty", "assets"] {
            try fm.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        try Data("# Trip".utf8).write(to: root.appending(path: "Trip.md"))
        try Data("# One".utf8).write(to: root.appending(path: "Trip/Day 1.md"))
        try Data("x".utf8).write(to: root.appending(path: "Trip/Day 1/Morning.txt"))
        try Data("<h1>Soup</h1>".utf8).write(to: root.appending(path: "Recipes/Soup.html"))
        try Data([1]).write(to: root.appending(path: "assets/p.png"))
        try Data([1]).write(to: root.appending(path: "photo.png"))
        try Data(#"{"hello": 1}"#.utf8).write(to: root.appending(path: "data.json"))
        try Data("a".utf8).write(to: root.appending(path: "Alpha.md"))
        return root
    }

    @Test func foldersBecomeParentPages() throws {
        let root = try importFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = WorkspaceImport.plan([root])
        let rows = plan.items.map { item in "\(item.parent.map(String.init) ?? "-") \(item.name)" }
        #expect(rows == ["- Alpha", "- Recipes", "1 Soup", "- Trip", "3 Day 1", "4 Morning"])
        guard case .folder = plan.items[1].source else { return #expect(Bool(false), "Recipes isn't a folder page") }
        guard case .document(_, .html) = plan.items[2].source else { return #expect(Bool(false)) }
        #expect(plan.items.allSatisfy { $0.root.standardizedFileURL == root.standardizedFileURL })
        // The stray JSON is reported; pictures and assets/ are attachments, not skipped files.
        #expect(plan.skipped == [WorkspaceImport.Skipped(name: "data.json", reason: .notAPage)])
    }

    /// An export's documents come back in their order, not by name, with the ids they had.
    @Test func stampedDocumentsComeBackInTheirOrder() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zebra = TransferStamp.stamp("# Zebra", id: "z", order: 0, format: .markdown)
        let apple = TransferStamp.stamp("<html><head></head><body><h1>Apple</h1></body></html>", id: "a", order: 1, format: .html)
        try Data(zebra.utf8).write(to: root.appending(path: "Zebra.md"))
        try Data(apple.utf8).write(to: root.appending(path: "Apple.html"))
        try Data("# Mango".utf8).write(to: root.appending(path: "Mango.md"))
        let plan = WorkspaceImport.plan([root])
        #expect(plan.items.map(\.name) == ["Zebra", "Apple", "Mango"])
        #expect(plan.items.map(\.pageID) == ["z", "a", nil])
    }

    @Test func importedPagesKeepTheirIdsWhenFree() {
        let item = { (id: String?) in WorkspaceImport.Item(source: .folder(name: "x"), parent: nil, root: URL(filePath: "/"), pageID: id) }
        let (ids, links) = WorkspaceImport.assignIDs([item("free"), item("taken"), item("free"), item(nil)]) { $0 == "taken" }
        #expect(ids[0] == "free")
        #expect(ids[1] != "taken")
        // A second "free" gets its own id, but links to "free" stay with the page that kept it.
        #expect(ids[2] != "free")
        #expect(links == ["taken": ids[1]])
        #expect(Set(ids).count == 4)
    }

    /// Ids name files on a file system that ignores case: `ABC` must not land on `abc`'s file.
    @Test func keptIdsNeverCollideIgnoringCase() throws {
        let store = try DocumentStore.inMemory()
        _ = try store.create(id: "abc")
        #expect(try store.hasDocument(matching: "ABC"))
        #expect(try !store.hasDocument(matching: "abd"))
        let item = { (id: String) in WorkspaceImport.Item(source: .folder(name: "x"), parent: nil, root: URL(filePath: "/"), pageID: id) }
        let (ids, _) = WorkspaceImport.assignIDs([item("ABC"), item("Page-1"), item("page-1"), item("日本")]) { id in
            (try? store.hasDocument(matching: id)) ?? true
        }
        #expect(ids[0] != "ABC")
        #expect(ids[1] == "Page-1")
        #expect(ids[2] != "page-1")
        #expect(ids[3] != "日本")
    }

    @Test func linksAndMentionsFollowRenamedPages() {
        func text(_ value: String, href: String? = nil) -> JSONValue {
            var node: [String: JSONValue] = ["type": .string("text"), "text": .string(value)]
            if let href {
                node["marks"] = .array([.object(["type": .string("link"), "attrs": .object(["href": .string(href)])])])
            }
            return .object(node)
        }
        func mention(_ id: String) -> JSONValue {
            .object(["type": .string("mention"), "attrs": .object(["id": .string(id), "label": .string("Trip")])])
        }
        func doc(_ inline: [JSONValue]) -> JSONValue {
            .object(["type": .string("doc"), "content": .array([.object(["type": .string("paragraph"), "content": .array(inline)])])])
        }
        let before = doc([text("Trip", href: "hikki://page/old#b1"), mention("old"), text("hikki://page/other"), mention("other")])
        let after = doc([text("Trip", href: "hikki://page/new#b1"), mention("new"), text("hikki://page/other"), mention("other")])
        #expect(PageLink.rewrite(before, ids: ["old": "new"]) == after)
        #expect(PageLink.rewrite(before, ids: [:]) == before)
    }

    @Test func symbolicLinksInAChosenFolderNeverComeIn() throws {
        let root = try importFixture()
        let outside = FileManager.default.temporaryDirectory.appending(path: "outside-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside.appending(path: "id_rsa"))
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "Notes.md"), withDestinationURL: outside.appending(path: "id_rsa"))
        try FileManager.default.createSymbolicLink(at: root.appending(path: "Elsewhere"), withDestinationURL: outside)
        let plan = WorkspaceImport.plan([root])
        #expect(!plan.items.map(\.name).contains("Notes"))
        #expect(!plan.items.map(\.name).contains("Elsewhere"))
        #expect(plan.skipped.contains(WorkspaceImport.Skipped(name: "Notes.md", reason: .symbolicLink)))
        #expect(plan.skipped.contains(WorkspaceImport.Skipped(name: "Elsewhere", reason: .symbolicLink)))
    }

    @Test func chosenFilesImportAloneAndOthersAreReported() throws {
        let root = try importFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = WorkspaceImport.plan([root.appending(path: "Trip.md"), root.appending(path: "photo.png")])
        #expect(plan.items.map(\.name) == ["Trip"])
        #expect(plan.items[0].root.standardizedFileURL == root.standardizedFileURL)
        #expect(plan.skipped == [WorkspaceImport.Skipped(name: "photo.png", reason: .unsupported)])
    }

    @Test func linksMayClimbToTheChosenFolderButNotOut() throws {
        let root = try importFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.appending(path: "Trip")
        #expect(PageImport.localFile("../assets/p.png", base: base, root: root) != nil)
        #expect(PageImport.localFile("../assets/p.png", base: base) == nil)
        #expect(PageImport.localFile("../../p.png", base: base, root: root) == nil)
    }

    // MARK: - JSON round trip

    @Test func jsonExportImportsBackAsTheSameWorkspace() throws {
        let fm = FileManager.default
        let scratch = try makeTempDirectory()
        defer { try? fm.removeItem(at: scratch) }
        let source = try DocumentStore.inMemory()
        let sourceAssets = AssetStore(directory: scratch.appending(path: "source-assets"))
        let picture = try sourceAssets.save(Data([1, 2, 3]), fileExtension: "png")
        func page(_ title: String, parent: String? = nil, icon: String? = nil, body: String, image: String? = nil) throws -> String {
            // Written long ago: the import must keep these dates, not stamp its own.
            let created = Date(timeIntervalSince1970: 1_700_000_000)
            let record = try source.create(parentId: parent, now: created)
            var blocks: [JSONValue] = [
                .object(["type": .string("paragraph"), "content": .array([.object(["type": .string("text"), "text": .string(body)])])])
            ]
            if let image { blocks.append(.object(["type": .string("image"), "attrs": .object(["src": .string(image)])])) }
            try source.saveContent(
                Snapshot(
                    docId: record.id, content: .object(["type": .string("doc"), "content": .array(blocks)]), title: title, text: body,
                    wordCount: 1), now: created.addingTimeInterval(3_600))
            if let icon { try source.setIcon(icon, for: record.id, now: created.addingTimeInterval(7_200)) }
            return record.id
        }
        let trip = try page("Trip", icon: "🧭", body: "plans", image: picture)
        let day = try page("Day 1", parent: trip, body: "museum")
        let night = try page("Night", parent: day, body: "stars")
        _ = try page("Trip", body: "same title")
        // A page linking two others: a link to a block in one, a mention of the other.
        let links = try source.create(parentId: day, now: Date(timeIntervalSince1970: 1_700_000_000))
        let link: JSONValue = .object(["type": .string("link"), "attrs": .object(["href": .string("hikki://page/\(day)#b1")])])
        let linking: JSONValue = .object([
            "type": .string("doc"),
            "content": .array([
                .object([
                    "type": .string("paragraph"),
                    "content": .array([
                        .object([
                            "type": .string("text"), "text": .string("Day"),
                            "marks": .array([link]),
                        ]),
                        .object(["type": .string("mention"), "attrs": .object(["id": .string(night), "label": .string("Night")])]),
                    ]),
                ])
            ]),
        ])
        try source.saveContent(
            Snapshot(docId: links.id, content: linking, title: "Links", text: "Day", wordCount: 1),
            now: Date(timeIntervalSince1970: 1_700_003_600))
        try source.setCover("gradient:dusk", for: trip)
        let trashed = try page("Gone", body: "x")
        try source.moveToTrash(id: trashed)

        // Export, as the app does: the plan, each page file, its attachments.
        let folder = try WorkspaceExport.makeFolder(in: scratch, workspace: "Test")
        for entry in WorkspaceExport.plan(try source.pages(), fileExtension: "json", fallback: "Untitled") {
            let record = try #require(try source.document(id: entry.id))
            let (data, names) = try WorkspaceExport.pageFile(record)
            try WorkspaceExport.write(data, entry: entry, in: folder)
            for name in names { try WorkspaceExport.copyAsset(name, from: sourceAssets, to: folder) }
        }
        #expect(fm.fileExists(atPath: folder.appending(path: "Trip/Day 1/Night.json").path))
        #expect(fm.fileExists(atPath: folder.appending(path: "Trip 2.json").path))
        #expect(fm.fileExists(atPath: folder.appending(path: "assets/\(AssetStore.name(fromURL: picture)!)").path))
        #expect(!fm.fileExists(atPath: folder.appending(path: "Gone.json").path))

        // Import into an empty workspace, as the app does: parents first.
        let target = try DocumentStore.inMemory()
        let targetAssets = AssetStore(directory: scratch.appending(path: "target-assets"))
        let plan = WorkspaceImport.plan([folder])
        #expect(plan.skipped.isEmpty)
        var created: [String] = []
        for item in plan.items {
            guard case .pageFile(let url) = item.source else { return #expect(Bool(false), "not a page file") }
            created.append(
                try WorkspaceImport.importPageFile(
                    at: url, root: item.root, parentId: item.parent.map { created[$0] }, store: target, assets: targetAssets))
        }

        func shape(_ store: DocumentStore) throws -> [String] {
            try store.pages().map { page in
                let record = try #require(try store.document(id: page.id))
                return [
                    page.id, page.parentId ?? "-", page.title, page.icon ?? "-", record.cover ?? "-", record.content ?? "-",
                    "\(Int(record.createdAt.timeIntervalSince1970))", "\(Int(record.updatedAt.timeIntervalSince1970))",
                ].joined(separator: "|")
            }
            .sorted()
        }
        #expect(try shape(target) == shape(source))
        #expect(try target.activity(since: .distantPast).isEmpty)  // bringing pages back isn't writing in them
        #expect(targetAssets.file(named: AssetStore.name(fromURL: picture)!) != nil)
        // Sibling order survives too.
        #expect(try target.pages().filter { $0.parentId == nil }.map(\.title) == ["Trip", "Trip"])

        // Imported again (the same workspace), as the app does: the pages are copies with new ids under the same
        // shape, linking each other rather than the pages they were copied from.
        let again = WorkspaceImport.plan([folder])
        let (ids, renamed) = WorkspaceImport.assignIDs(again.items) { id in
            do { return try target.hasDocument(matching: id) } catch { return true }
        }
        var copies: [String] = []
        for (index, item) in again.items.enumerated() {
            guard case .pageFile(let url) = item.source else { continue }
            copies.append(
                try WorkspaceImport.importPageFile(
                    at: url, root: item.root, id: ids[index], parentId: item.parent.map { copies[$0] }, links: renamed, store: target,
                    assets: targetAssets))
        }
        #expect(copies == ids)
        #expect(Set(copies).isDisjoint(with: created))
        #expect(try target.pages().count == 10)
        let copied = try target.pages().filter { copies.contains($0.id) }
        let nightCopy = try #require(copied.first { $0.title == "Night" })
        let dayCopy = try #require(copied.first { $0.title == "Day 1" })
        #expect(dayCopy.id == nightCopy.parentId)
        let linksID = try #require(copied.first { $0.title == "Links" }).id
        let linksCopy = try #require(try target.document(id: linksID))
        let body = try #require(linksCopy.content)
        #expect(body.contains("hikki://page/\(dayCopy.id)#b1") && body.contains(#""id":"\#(nightCopy.id)""#))
        #expect(!body.contains(day) && !body.contains(night))
    }

    @Test func aFolderWithoutItsOwnDocumentIsAnEmptyPageWithItsName() throws {
        let store = try DocumentStore.inMemory()
        let parent = try store.create()
        let id = try WorkspaceImport.createFolderPage(named: "Recipes", parentId: parent.id, store: store)
        let record = try #require(try store.document(id: id))
        #expect(record.title == "Recipes" && record.parentId == parent.id && record.content != nil)
    }

    @Test func pageFilesFromANewerHikkiAreReportedNotGuessed() throws {
        let folder = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(#"{"format": 99, "id": "x", "title": "Later"}"#.utf8).write(to: folder.appending(path: "x.json"))
        let plan = WorkspaceImport.plan([folder])
        #expect(plan.items.isEmpty)
        #expect(plan.skipped == [WorkspaceImport.Skipped(name: "x.json", reason: .newerFormat)])
    }

    @Test func aFlatFolderOfPageFilesRebuildsItsTree() throws {
        let scratch = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let store = try DocumentStore.inMemory()
        let parent = try store.create(id: "parent")
        _ = try store.create(id: "child", parentId: parent.id)
        let files = PageFiles(root: scratch)
        for record in try store.allDocuments() { try files.write(try PageFile(record: record)) }
        let plan = WorkspaceImport.plan([files.directory])
        #expect(plan.items.map(\.name) == ["parent", "child"])
        #expect(plan.items.map(\.parent) == [nil, 0])
    }
}
