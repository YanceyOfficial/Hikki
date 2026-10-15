import Foundation

// Bulk import and export (Settings → Workspace → Import & Export): the parts that need no editor. The app runs the
// job (`Hikki/Sources/BulkTransfer.swift`) and asks the editor only to convert Markdown / HTML, one page at a time.

/// A whole workspace as a folder that mirrors the page tree: a page is `Title.<ext>`, a page with subpages also has a
/// folder `Title/` beside it holding theirs, and every attachment sits once in the export's `assets/`, which each
/// document links to relatively. Names are file-system safe and unique among siblings.
public enum WorkspaceExport {
    /// What a whole-workspace export can be written as. JSON is the page files as stored.
    public enum Format: String, Sendable, CaseIterable, Identifiable {
        case markdown, html, json

        public var id: String { rawValue }

        public var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .html: "html"
            case .json: "json"
            }
        }
    }

    /// One page's place in the export.
    public struct Entry: Equatable, Sendable {
        public var id: String
        /// Relative to the export folder, e.g. `Trip/Day 1.md`.
        public var path: String
        /// How many folders down the document is (0 at the top), so its links reach `assets/` with that many `../`.
        public var depth: Int

        public init(id: String, path: String, depth: Int) {
            self.id = id
            self.path = path
            self.depth = depth
        }

        /// The prefix its attachment links get (`assets/`, `../assets/`…).
        public var assetPrefix: String { String(repeating: "../", count: depth) + "assets/" }
    }

    /// The folder attachments go in, at the top of the export.
    public static let assetsFolder = "assets"

    /// Every live page's file, parents before their children, siblings in their order. A page whose parent isn't
    /// among `pages` sits at the top.
    public static func plan(_ pages: [PageSummary], fileExtension: String, fallback: String) -> [Entry] {
        let ids = Set(pages.map(\.id))
        var children: [String?: [PageSummary]] = [:]
        for page in pages {
            let parent = page.parentId.flatMap { ids.contains($0) && $0 != page.id ? $0 : nil }
            children[parent, default: []].append(page)
        }
        for key in children.keys {
            children[key]?.sort { ($0.sortKey, $0.createdAt, $0.id) < ($1.sortKey, $1.createdAt, $1.id) }
        }
        var entries: [Entry] = []
        var visited = Set<String>()
        func walk(_ parent: String?, folder: String, depth: Int) {
            // The top level keeps the attachments folder's name free.
            var taken: Set<String> = depth == 0 ? [key(assetsFolder)] : []
            for page in children[parent] ?? [] where visited.insert(page.id).inserted {
                let name = uniqueName(PageExport.fileName(for: page.title, fallback: fallback), taken: &taken)
                entries.append(Entry(id: page.id, path: folder + name + "." + fileExtension, depth: depth))
                walk(page.id, folder: folder + name + "/", depth: depth + 1)
            }
        }
        walk(nil, folder: "", depth: 0)
        return entries
    }

    /// `name`, or `name 2`, `name 3`… — the first not in `taken` (compared as the file system does: case and
    /// Unicode normalization don't count), which it joins.
    public static func uniqueName(_ name: String, taken: inout Set<String>) -> String {
        var candidate = name
        var number = 2
        while taken.contains(key(candidate)) {
            candidate = "\(name) \(number)"
            number += 1
        }
        taken.insert(key(candidate))
        return candidate
    }

    static func key(_ name: String) -> String { name.precomposedStringWithCanonicalMapping.lowercased() }

    /// A new folder for the export inside `destination` (`<workspace> <yyyy-MM-dd>`, numbered when taken), created.
    public static func makeFolder(in destination: URL, workspace: String, date: Date = .now) throws -> URL {
        let day = date.formatted(.iso8601.year().month().day())
        let base = PageExport.fileName(for: "\(workspace) \(day)", fallback: "Hikki \(day)")
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []).map(key))
        var taken = existing
        let folder = destination.appending(path: uniqueName(base, taken: &taken), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    /// A Markdown / HTML document (the editor's) ready to write: its attachment links pointed at the export's
    /// `assets/`, and the attachments it needs.
    public static func document(text: String, entry: Entry) -> (data: Data, assets: [String]) {
        let (relinked, names) = PageExport.relinkAssets(in: text, prefix: entry.assetPrefix)
        return (Data(relinked.utf8), names)
    }

    /// The page file as stored, and the attachments it names (body and cover) — kept by name, so they import back
    /// under the same links.
    public static func pageFile(_ record: DocumentRecord) throws -> (data: Data, assets: [String]) {
        var names = (try record.contentValue()).map(assetNames) ?? []
        if let cover = record.cover.flatMap(AssetStore.name(fromURL:)), !names.contains(cover) { names.append(cover) }
        return (try PageExport.json(record), names)
    }

    /// Every attachment named in a page body (`hikki-editor://assets/<name>` anywhere in it), in order, each once.
    public static func assetNames(in content: JSONValue) -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        func walk(_ value: JSONValue) {
            switch value {
            case .string(let text):
                if let name = AssetStore.name(fromURL: text), seen.insert(name).inserted { names.append(name) }
            case .array(let items): items.forEach(walk)
            case .object(let object): object.keys.sorted().forEach { walk(object[$0]!) }
            default: break
            }
        }
        walk(content)
        return names
    }

    /// Writes one document at its place in the export (folders made as needed).
    public static func write(_ data: Data, entry: Entry, in folder: URL) throws {
        let file = folder.appending(path: entry.path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    /// Copies an attachment into the export's `assets/` unless it is there already. False when the store has no
    /// such file.
    @discardableResult
    public static func copyAsset(_ name: String, from assets: AssetStore, to folder: URL) throws -> Bool {
        guard let source = assets.file(named: name) else { return false }
        let target = folder.appending(path: assetsFolder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let file = target.appending(path: name)
        if !FileManager.default.fileExists(atPath: file.path) { try FileManager.default.copyItem(at: source, to: file) }
        return true
    }
}

/// Many files and folders brought in at once, the folders' structure becoming the page tree: a folder is a page
/// (empty, titled with its name) whose documents are its subpages — unless a document beside it has the folder's
/// name, which then is that page (how an export writes a page with subpages). Hikki's own page files (JSON) come
/// back as they were: title, icon, cover, body and their place in the tree — by their `parentId` too, so a flat
/// folder of page files (a workspace's `pages/`) rebuilds its tree.
public enum WorkspaceImport {
    /// Markdown / HTML / text larger than this aren't read.
    public static let documentLimit = 20 * 1024 * 1024
    /// Page files larger than this aren't read.
    public static let pageFileLimit = 100 * 1024 * 1024

    public enum Source: Equatable, Sendable {
        /// Converted by the editor.
        case document(URL, ImportFormat)
        /// A Hikki page file.
        case pageFile(URL)
        /// A folder with no document of its own: an empty page with its name.
        case folder(name: String)
    }

    /// One page to make. Items come parents first; `parent` is the index of the item it goes under.
    public struct Item: Equatable, Sendable {
        public var source: Source
        public var parent: Int?
        /// The folder the user chose (or the chosen file's folder): relative links reach files inside it only.
        public var root: URL

        /// The file's name without its extension (a document's title when it has none of its own), or the folder's.
        public var name: String {
            switch source {
            case .document(let url, _), .pageFile(let url): url.deletingPathExtension().lastPathComponent
            case .folder(let name): name
            }
        }
    }

    public enum Reason: String, Error, Equatable, Sendable {
        /// Not Markdown, HTML, text or a page file.
        case unsupported
        case tooLarge
        /// JSON that isn't a Hikki page.
        case notAPage
        /// A page file from a newer Hikki.
        case newerFormat
        /// A page file of a page in the trash.
        case inTrash
        /// Couldn't be read or converted.
        case failed
        /// A symbolic link: it may point anywhere on the disk, so it never comes in.
        case symbolicLink
    }

    /// A file left out, by name (shown in the summary; never logged — it may be a title).
    public struct Skipped: Equatable, Sendable {
        public var name: String
        public var reason: Reason

        public init(name: String, reason: Reason) {
            self.name = name
            self.reason = reason
        }
    }

    public struct Plan: Equatable, Sendable {
        public var items: [Item]
        public var skipped: [Skipped]
    }

    /// What a page file says about its place, read before importing.
    struct Header: Decodable {
        var format: Int
        var id: String
        var title: String
        var parentId: String?
        var sortKey: Double?
        var deletedAt: Date?
    }

    private final class Node {
        let source: Source
        let root: URL
        let sortKey: Double?
        let pageID: String?
        let pageParent: String?
        var children: [Node] = []

        init(source: Source, root: URL, header: Header? = nil) {
            self.source = source
            self.root = root
            sortKey = header?.sortKey
            pageID = header?.id
            pageParent = header?.parentId
        }

        var name: String {
            switch source {
            case .document(let url, _), .pageFile(let url): url.lastPathComponent
            case .folder(let name): name
            }
        }
    }

    /// The pages the chosen files and folders make, parents first. A chosen folder's contents go to the top level
    /// (the folder itself is only the container, like an export's); a chosen file is one page.
    public static func plan(_ urls: [URL]) -> Plan {
        var skipped: [Skipped] = []
        var roots: [Node] = []
        for url in urls {
            if isFolder(url) {
                roots += contents(of: url, root: url, skipped: &skipped)
            } else if let node = node(for: url, root: url.deletingLastPathComponent(), skipped: &skipped, reportUnsupported: true) {
                roots.append(node)
            }
        }
        roots = reparent(roots)
        var items: [Item] = []
        func flatten(_ nodes: [Node], parent: Int?) {
            for node in nodes {
                items.append(Item(source: node.source, parent: parent, root: node.root))
                flatten(node.children, parent: items.count - 1)
            }
        }
        flatten(roots, parent: nil)
        return Plan(items: items, skipped: skipped)
    }

    private static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func contents(of folder: URL, root: URL, skipped: inout [Skipped]) -> [Node] {
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])) ?? []
        var documents: [Node] = []
        var folders: [URL] = []
        for entry in entries {
            // A link inside the chosen folder could reach any file or folder on the disk: left out.
            if (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                skipped.append(Skipped(name: entry.lastPathComponent, reason: .symbolicLink))
                continue
            }
            if isFolder(entry) {
                // An export's attachments: linked from the documents, not pages of their own.
                if entry.lastPathComponent.lowercased() != WorkspaceExport.assetsFolder { folders.append(entry) }
            } else if let node = node(for: entry, root: root, skipped: &skipped, reportUnsupported: false) {
                documents.append(node)
            }
        }
        var nodes = documents
        for sub in folders {
            let children = contents(of: sub, root: root, skipped: &skipped)
            let name = WorkspaceExport.key(sub.lastPathComponent)
            if let page = documents.filter({ WorkspaceExport.key(stem($0)) == name }).min(by: { preference($0) < preference($1) }) {
                page.children += children
            } else if !children.isEmpty {
                let node = Node(source: .folder(name: sub.lastPathComponent), root: root)
                node.children = children
                nodes.append(node)
            }
        }
        return sorted(nodes)
    }

    private static func stem(_ node: Node) -> String {
        switch node.source {
        case .document(let url, _), .pageFile(let url): url.deletingPathExtension().lastPathComponent
        case .folder(let name): name
        }
    }

    /// Which of several documents named like a folder is its page: a page file, then Markdown, HTML, text.
    private static func preference(_ node: Node) -> Int {
        switch node.source {
        case .pageFile: 0
        case .document(_, .markdown): 1
        case .document(_, .html): 2
        case .document(_, .text): 3
        case .folder: 4
        }
    }

    /// Page files in their stored order, the rest by name (as Finder lists them).
    private static func sorted(_ nodes: [Node]) -> [Node] {
        nodes.sorted { a, b in
            switch (a.sortKey, b.sortKey) {
            case (let x?, let y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    private static func node(for url: URL, root: URL, skipped: inout [Skipped], reportUnsupported: Bool) -> Node? {
        let name = url.lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if url.pathExtension.lowercased() == "json" {
            guard size <= pageFileLimit else {
                skipped.append(Skipped(name: name, reason: .tooLarge))
                return nil
            }
            switch header(of: url) {
            case .success(let header) where header.deletedAt != nil:
                skipped.append(Skipped(name: name, reason: .inTrash))
                return nil
            case .success(let header):
                return Node(source: .pageFile(url), root: root, header: header)
            case .failure(let reason):
                skipped.append(Skipped(name: name, reason: reason))
                return nil
            }
        }
        guard let format = ImportFormat(fileExtension: url.pathExtension) else {
            if reportUnsupported { skipped.append(Skipped(name: name, reason: .unsupported)) }
            return nil
        }
        guard size <= documentLimit else {
            skipped.append(Skipped(name: name, reason: .tooLarge))
            return nil
        }
        return Node(source: .document(url, format), root: root)
    }

    private static func header(of url: URL) -> Result<Header, Reason> {
        guard let data = try? Data(contentsOf: url) else { return .failure(.failed) }
        guard let header = try? PageFiles.decoder.decode(Header.self, from: data), PageFiles.isValid(header.id) else {
            return .failure(.notAPage)
        }
        guard header.format <= PageFile.currentFormat else { return .failure(.newerFormat) }
        return .success(header)
    }

    /// Top-level page files whose `parentId` names another imported page go under it (a flat folder of page files);
    /// never into their own subtree.
    private static func reparent(_ roots: [Node]) -> [Node] {
        var byID: [String: Node] = [:]
        var parentOf: [ObjectIdentifier: Node] = [:]
        func index(_ node: Node, parent: Node?) {
            if let id = node.pageID, byID[id] == nil { byID[id] = node }
            if let parent { parentOf[ObjectIdentifier(node)] = parent }
            for child in node.children { index(child, parent: node) }
        }
        for root in roots { index(root, parent: nil) }
        var kept: [Node] = []
        var moved: [Node] = []
        for node in roots {
            guard let parentID = node.pageParent, let target = byID[parentID], target !== node else {
                kept.append(node)
                continue
            }
            // Not under itself: walk up from the target.
            var cursor: Node? = target
            var cycle = false
            while let current = cursor {
                if current === node {
                    cycle = true
                    break
                }
                cursor = parentOf[ObjectIdentifier(current)]
            }
            if cycle {
                kept.append(node)
            } else {
                target.children.append(node)
                parentOf[ObjectIdentifier(node)] = target
                moved.append(target)
            }
        }
        for target in moved { target.children = sorted(target.children) }
        return kept
    }

    /// Imports a page file as a new page under `parentId`: its title, icon, cover, favorite and lock, and body.
    /// It keeps its id when the store has no page by that id (links between imported pages keep working), else
    /// gets a new one. Attachments it names that the store lacks are copied from the nearest `assets/` folder above
    /// it (inside `root`) under the same names. Returns the page's id in this workspace.
    public static func importPageFile(
        at url: URL, root: URL, parentId: String?, store: DocumentStore, assets: AssetStore
    ) throws -> String {
        let page = try PageFiles.decode(Data(contentsOf: url))
        let id = try store.document(id: page.id) == nil ? page.id : UUID().uuidString
        let base = url.deletingLastPathComponent()
        let copy: (String) -> Void = { name in
            guard assets.file(named: name) == nil, let file = assetFile(name, from: base, root: root) else { return }
            _ = try? assets.importCopy(of: file, named: name)
        }
        if let content = page.content { WorkspaceExport.assetNames(in: content).forEach(copy) }
        if let cover = page.cover.flatMap(AssetStore.name(fromURL:)) { copy(cover) }
        // As it was — created and edited dates included — in one write; restoring a page isn't writing in it.
        try store.insertImported(page, id: id, parentId: parentId)
        return id
    }

    /// A folder with no document of its own, as an empty page titled with its name under `parentId`.
    public static func createFolderPage(named name: String, parentId: String?, store: DocumentStore) throws -> String {
        let record = try store.create(parentId: parentId)
        let empty: JSONValue = .object(["type": .string("doc"), "content": .array([.object(["type": .string("paragraph")])])])
        try store.saveContent(Snapshot(docId: record.id, content: empty, title: name, text: "", wordCount: 0))
        return record.id
    }

    /// `assets/<name>` in the page file's folder or the nearest folder above it, up to `root`.
    static func assetFile(_ name: String, from base: URL, root: URL) -> URL? {
        guard AssetStore.isValidName(name) else { return nil }
        let boundary = root.standardizedFileURL.resolvingSymlinksInPath().path
        var folder = base.standardizedFileURL.resolvingSymlinksInPath()
        while folder.path.hasPrefix(boundary) {
            let file = folder.appending(path: WorkspaceExport.assetsFolder).appending(path: name)
            if FileManager.default.fileExists(atPath: file.path) { return file }
            guard folder.path != boundary else { break }
            folder = folder.deletingLastPathComponent()
        }
        return nil
    }
}
