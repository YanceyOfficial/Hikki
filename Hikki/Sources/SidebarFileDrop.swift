import HikkiCore
import SwiftUI
import UniformTypeIdentifiers

/// Files dragged onto the sidebar (Mac/iPad) from Finder or Files: Markdown, HTML and text documents, or folders of
/// them, become pages — on a page row as its children, anywhere else at the top level. The Mac hands over file URLs
/// (read where they are, so pictures beside a document come along); iPad drags carry the document's type, loaded as a
/// copy. The import itself is ContentView's (`Navigator.importDrop` → `AppModel.importFiles`), which has the editor
/// that converts them.
enum SidebarFileDrop {
    static let types: [UTType] = [.fileURL] + PageImport.documentTypes

    /// The dragged items that may import — a page row's own drag (a page link) is not one.
    static func importable(_ providers: [NSItemProvider]) -> [NSItemProvider] {
        providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || PageImport.documentType(registered: $0.registeredTypeIdentifiers, suggestedName: $0.suggestedName) != nil
        }
    }

    static func carriesFiles(_ info: DropInfo) -> Bool {
        !importable(info.itemProviders(for: types)).isEmpty
    }

    /// Reads the dropped files and hands them to the window's import; false when nothing in the drop imports.
    static func perform(_ info: DropInfo, parent: String?, navigator: Navigator) -> Bool {
        let providers = importable(info.itemProviders(for: types))
        guard !providers.isEmpty else { return false }
        Task {
            let urls = await load(providers)
            let files = PageImport.importable(urls)
            Log.info(
                "files dropped on the sidebar", category: "import",
                context: ["items": "\(providers.count)", "files": "\(files.count)", "nested": parent == nil ? "no" : "yes"])
            guard !files.isEmpty else { return }
            if let parent { navigator.expanded.insert(parent) }
            navigator.importDrop = ImportDrop(urls: files, parentID: parent)
        }
        return true
    }

    /// The dropped items as files: file URLs as they are, typed documents (iPad) as temporary copies.
    static func load(_ providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await load(provider) { urls.append(url) }
        }
        return urls
    }

    private static func load(_ provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
        }
        guard
            let type = PageImport.documentType(registered: provider.registeredTypeIdentifiers, suggestedName: provider.suggestedName)
        else { return nil }
        let name = PageImport.fileName(suggestedName: provider.suggestedName, type: type)
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { file, error in
                // The file is gone once this returns: keep a copy, under its own name (the format is read from it).
                guard let file else {
                    if let error { Log.warn("dropped file unreadable: \(error)", category: "import") }
                    return continuation.resume(returning: nil)
                }
                let folder = FileManager.default.temporaryDirectory.appending(
                    path: "hikki-drop-\(UUID().uuidString)", directoryHint: .isDirectory)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let copy = folder.appending(path: name)
                    try FileManager.default.copyItem(at: file, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    Log.warn("dropped file not copied: \(error)", category: "import")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// Files dropped on the sidebar outside any page row: new pages at the top level, the sidebar outlined meanwhile.
struct SidebarFileDropDelegate: DropDelegate {
    let navigator: Navigator
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool { SidebarFileDrop.carriesFiles(info) }
    func dropEntered(info: DropInfo) { isTargeted = SidebarFileDrop.carriesFiles(info) }
    func dropExited(info: DropInfo) { isTargeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        return SidebarFileDrop.perform(info, parent: nil, navigator: navigator)
    }
}
