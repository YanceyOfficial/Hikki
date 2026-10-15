import Foundation
import UniformTypeIdentifiers

/// Exporting a page to files. Markdown and HTML come from the editor (`window.hikki.exportPage`); this names the
/// export, points its attachments at copies next to it and packs the result: a single file when the page attaches
/// nothing, otherwise a folder holding the document and an `assets/` folder it links into (relative links, so the
/// folder can move as a whole). JSON is the page file itself, as stored in the workspace folder.
public enum PageExport {
    public enum Format: String, Sendable, CaseIterable, Identifiable {
        case markdown, html, pdf, json

        public var id: String { rawValue }

        public var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .html: "html"
            case .json: "json"
            case .pdf: "pdf"
            }
        }

        /// The file type the save panel is told about: it adds (and hides) the extension from it, so a name typed
        /// without one still ends up as `name.md`.
        public var contentType: UTType {
            switch self {
            case .markdown: UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
            case .html: .html
            case .json: .json
            case .pdf: .pdf
            }
        }
    }

    /// Every type an export can be saved as (the formats', and a folder for a page with attachments).
    public static var writableContentTypes: [UTType] { Format.allCases.map(\.contentType) + [.folder] }

    /// A file name from the page's title: no path separators, colons or control characters, not hidden, not too
    /// long; `fallback` when nothing is left.
    public static func fileName(for title: String, fallback: String) -> String {
        let cleaned = title.unicodeScalars
            .map { scalar -> Character in
                if CharacterSet.controlCharacters.contains(scalar) || "/\\:".unicodeScalars.contains(scalar) { return "-" }
                return Character(scalar)
            }
        var name = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        name = String(name.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallback : name
    }

    /// Rewrites every attachment URL (`hikki-editor://assets/<name>`) in an exported document to `<prefix><name>`
    /// (`assets/<name>`; a page deeper in a workspace export climbs to the export's one `assets/` with `../`) and
    /// returns the names it found, in order, each once.
    public static func relinkAssets(in text: String, prefix: String = "assets/") -> (text: String, assets: [String]) {
        var names: [String] = []
        var seen = Set<String>()
        // `AssetStore.urlPrefix`, then the name.
        let relinked = text.replacing(#/hikki-editor://assets/([\w.\-]+)/#) { match in
            let name = String(match.output.1)
            guard AssetStore.isValidName(name) else { return String(match.output.0) }
            if seen.insert(name).inserted { names.append(name) }
            return prefix + name
        }
        return (relinked, names)
    }

    /// The export as a file wrapper: `document` alone, or — with attachments — a folder named `name` holding
    /// `name.<ext>` and `assets/`. Attachments whose file is missing are left out (their links stay).
    public static func package(document: Data, name: String, fileExtension: String, assets: [(name: String, file: URL)])
        -> FileWrapper
    {
        let documentName = "\(name).\(fileExtension)"
        let file = FileWrapper(regularFileWithContents: document)
        file.preferredFilename = documentName
        let attachments = assets.compactMap { asset -> FileWrapper? in
            guard let data = try? Data(contentsOf: asset.file) else { return nil }
            let wrapper = FileWrapper(regularFileWithContents: data)
            wrapper.preferredFilename = asset.name
            return wrapper
        }
        guard !attachments.isEmpty else { return file }
        let assetsFolder = FileWrapper(directoryWithFileWrappers: [:])
        assetsFolder.preferredFilename = "assets"
        for attachment in attachments { assetsFolder.addFileWrapper(attachment) }
        let folder = FileWrapper(directoryWithFileWrappers: [:])
        folder.preferredFilename = name
        folder.addFileWrapper(file)
        folder.addFileWrapper(assetsFolder)
        return folder
    }

    /// The page as stored in the workspace folder (format-versioned JSON, the body as Tiptap JSON).
    public static func json(_ record: DocumentRecord) throws -> Data {
        try PageFiles.encoder.encode(try PageFile(record: record))
    }
}
