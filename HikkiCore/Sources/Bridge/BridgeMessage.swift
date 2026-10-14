import Foundation

/// Mirror of editor/src/protocol.ts. Bump both versions together.
public enum BridgeProtocol {
    public static let version = 16

    /// Whether a script message may reach the shell. WebKit gives every frame of the web view the message
    /// handlers, embedded third-party pages included, so only the main frame, loaded from the editor's own
    /// scheme, is listened to.
    public static func trustsFrame(isMainFrame: Bool, scheme: String?, editorScheme: String) -> Bool {
        isMainFrame && scheme?.lowercased() == editorScheme.lowercased()
    }
}

public struct Snapshot: Codable, Sendable, Equatable {
    public var docId: String
    /// Body only — the title is a page property.
    public var content: JSONValue
    public var title: String
    public var text: String
    public var wordCount: Int

    public init(docId: String, content: JSONValue, title: String, text: String, wordCount: Int) {
        self.docId = docId
        self.content = content
        self.title = title
        self.text = text
        self.wordCount = wordCount
    }
}

/// A heading of the open page, for the inspector's outline (`id` is the block to scroll to; nil before the
/// editor stamped ids).
public struct OutlineHeading: Codable, Sendable, Equatable {
    public var id: String?
    public var level: Int
    public var text: String

    public init(id: String?, level: Int, text: String) {
        self.id = id
        self.level = level
        self.text = text
    }
}

/// Messages posted by the web editor to the native shell.
public enum BridgeMessage: Sendable, Equatable {
    case ready(protocolVersion: Int)
    case changed(Snapshot)
    case activeFormats([String])
    /// The open page's outline and size for the inspector: on load, then throttled as it changes.
    case pageInfo(docId: String, headings: [OutlineHeading], words: Int, characters: Int)
    /// The heading the reader is in changed (the page's scroll-spy); nil above the first heading.
    case activeHeading(docId: String, id: String?)
    case log(level: LogLevel, message: String, context: [String: String]?)
    case setIcon(docId: String, icon: String?)
    case setCover(docId: String, cover: String?)
    /// Expects the asset URL as the reply.
    case saveAsset(fileExtension: String, data: Data)
    /// Chunked upload of a large file (video, audio, attachment). `beginUpload` replies with the upload id,
    /// `finishUpload` with the asset URL.
    case beginUpload(fileExtension: String, size: Int)
    case uploadChunk(id: String, data: Data)
    case finishUpload(id: String)
    case cancelUpload(id: String)
    /// Open an attachment with the system (Quick Look / default app), never inside the web view.
    case openAsset(url: String, name: String?)
    /// A page link was clicked (with the block to scroll to, for a link to a block).
    case openPage(id: String, block: String?)
    /// A page was dropped on the right edge of the page: open it in the split pane.
    case openInSplit(id: String)
    /// Any other link was clicked: the system opens it.
    case openLink(url: String)
    /// Furigana: expects `text` split into runs — `[{text, reading?}]`, a reading per kanji run — as the reply (nil
    /// when there is none).
    case suggestReading(text: String)
    /// A link card's details: expects `{title, description, icon}` (each may be null), or nil, as the reply.
    case linkPreview(url: String)
}

public enum BridgeError: Error, Equatable {
    case notJSON
    case unknownType(String)
    case invalidPayload(String)
}

/// What `window.hikki.loadDocument(page)` receives (mirror of `PagePayload` in protocol.ts).
public enum PagePayload {
    public static func make(from record: DocumentRecord) throws -> [String: Any] {
        [
            "id": record.id,
            "title": record.title,
            "icon": record.icon ?? NSNull(),
            "cover": record.cover ?? NSNull(),
            "locked": record.isLocked,
            "content": try record.contentValue()?.foundationObject() ?? NSNull(),
        ]
    }
}

extension BridgeMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, snapshot, active, level, message, context, docId, icon, cover, fileExtension, dataBase64
        case size, id, url, block, text, headings, words, characters, name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "ready": self = .ready(protocolVersion: try c.decode(Int.self, forKey: .protocolVersion))
        case "changed": self = .changed(try c.decode(Snapshot.self, forKey: .snapshot))
        case "activeFormats": self = .activeFormats(try c.decode([String].self, forKey: .active))
        case "activeHeading":
            self = .activeHeading(docId: try c.decode(String.self, forKey: .docId), id: try c.decodeIfPresent(String.self, forKey: .id))
        case "pageInfo":
            self = .pageInfo(
                docId: try c.decode(String.self, forKey: .docId), headings: try c.decode([OutlineHeading].self, forKey: .headings),
                words: try c.decode(Int.self, forKey: .words), characters: try c.decode(Int.self, forKey: .characters))
        case "log":
            self = .log(
                level: try c.decode(LogLevel.self, forKey: .level),
                message: try c.decode(String.self, forKey: .message),
                context: try c.decodeIfPresent([String: String].self, forKey: .context)
            )
        case "setIcon":
            self = .setIcon(docId: try c.decode(String.self, forKey: .docId), icon: try c.decodeIfPresent(String.self, forKey: .icon))
        case "setCover":
            self = .setCover(docId: try c.decode(String.self, forKey: .docId), cover: try c.decodeIfPresent(String.self, forKey: .cover))
        case "saveAsset":
            guard let data = Data(base64Encoded: try c.decode(String.self, forKey: .dataBase64)) else {
                throw BridgeError.invalidPayload("saveAsset: dataBase64 is not base64")
            }
            self = .saveAsset(fileExtension: try c.decode(String.self, forKey: .fileExtension), data: data)
        case "beginUpload":
            self = .beginUpload(
                fileExtension: try c.decode(String.self, forKey: .fileExtension), size: try c.decode(Int.self, forKey: .size))
        case "uploadChunk":
            guard let data = Data(base64Encoded: try c.decode(String.self, forKey: .dataBase64)) else {
                throw BridgeError.invalidPayload("uploadChunk: dataBase64 is not base64")
            }
            self = .uploadChunk(id: try c.decode(String.self, forKey: .id), data: data)
        case "finishUpload": self = .finishUpload(id: try c.decode(String.self, forKey: .id))
        case "cancelUpload": self = .cancelUpload(id: try c.decode(String.self, forKey: .id))
        case "openAsset":
            self = .openAsset(url: try c.decode(String.self, forKey: .url), name: try c.decodeIfPresent(String.self, forKey: .name))
        case "openPage":
            self = .openPage(id: try c.decode(String.self, forKey: .id), block: try c.decodeIfPresent(String.self, forKey: .block))
        case "openInSplit":
            self = .openInSplit(id: try c.decode(String.self, forKey: .id))
        case "openLink": self = .openLink(url: try c.decode(String.self, forKey: .url))
        case "suggestReading": self = .suggestReading(text: try c.decode(String.self, forKey: .text))
        case "linkPreview": self = .linkPreview(url: try c.decode(String.self, forKey: .url))
        default: throw BridgeError.unknownType(type)
        }
    }

    /// Decodes a `WKScriptMessage.body` (Foundation dictionaries/arrays bridged from JS).
    public static func decode(scriptMessageBody body: Any) throws -> BridgeMessage {
        try JSONDecoder().decode(BridgeMessage.self, from: jsonData(from: body))
    }
}

extension Snapshot {
    /// Decodes the return value of `window.hikki.flush()`.
    public static func decode(scriptResult body: Any) throws -> Snapshot {
        try JSONDecoder().decode(Snapshot.self, from: jsonData(from: body))
    }
}

private func jsonData(from body: Any) throws -> Data {
    guard JSONSerialization.isValidJSONObject(body) else { throw BridgeError.notJSON }
    return try JSONSerialization.data(withJSONObject: body)
}
