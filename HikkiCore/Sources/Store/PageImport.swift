import Foundation

/// Importing pages from files: which files a chosen folder holds, and the pictures and attachments a document links
/// by relative path (an export's `assets/`, a Markdown folder's images), brought into the workspace's assets.
public enum PageImport {
    /// The documents in a chosen folder (its own level, sorted by name): Markdown, HTML and text files.
    public static func documents(in folder: URL) -> [URL] {
        let names =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        return
            names
            .filter { ImportFormat(fileExtension: $0.pathExtension) != nil }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// The file a relative link in a document points at — only inside `base` (the document's folder): no scheme, no
    /// absolute path, nothing that climbs out with `..`; nil otherwise or when no such file exists.
    public static func localFile(_ link: String, base: URL) -> URL? {
        let raw = link.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, !raw.hasPrefix("/"), !raw.hasPrefix("#"), URL(string: raw)?.scheme == nil,
            raw.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*:"#, options: .regularExpression) == nil
        else { return nil }
        let path = (raw.split(separator: "#").first.map(String.init) ?? raw).split(separator: "?").first.map(String.init) ?? raw
        let decoded = path.removingPercentEncoding ?? path
        let root = base.standardizedFileURL.resolvingSymlinksInPath()
        let file = root.appending(path: decoded).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        return file
    }

    /// Node types whose `src` is a file (pictures, video, audio, attachments).
    static let fileNodes: Set<String> = ["image", "video", "audio", "fileAttachment"]

    /// The content with every relative `src` that names a file inside `base` replaced by what `copy` makes of that
    /// file (its asset URL); one copy per file, however often it appears. A link `copy` can't take (nil, or an error)
    /// is left as it was.
    public static func relinkLocalFiles(
        in content: JSONValue, base: URL, copy: (URL) throws -> String?
    ) -> (content: JSONValue, copied: Int) {
        var copied: [URL: String] = [:]
        func walk(_ value: JSONValue) -> JSONValue {
            switch value {
            case .array(let items):
                return .array(items.map(walk))
            case .object(var object):
                if case .string(let type) = object["type"], fileNodes.contains(type),
                    case .object(var attrs) = object["attrs"], case .string(let src) = attrs["src"],
                    let file = localFile(src, base: base)
                {
                    if let url = copied[file] ?? (try? copy(file)) ?? nil {
                        copied[file] = url
                        attrs["src"] = .string(url)
                        if case .string(let name)? = attrs["name"], name.isEmpty || name == src {
                            attrs["name"] = .string(file.lastPathComponent)
                        }
                        object["attrs"] = .object(attrs)
                    }
                }
                if let children = object["content"] { object["content"] = walk(children) }
                return .object(object)
            default:
                return value
            }
        }
        let result = walk(content)
        return (result, copied.count)
    }
}
