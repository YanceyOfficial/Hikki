import Foundation

/// Mirror of editor/src/protocol.ts. Bump both versions together.
public enum BridgeProtocol {
    public static let version = 9
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

/// Messages posted by the web editor to the native shell.
public enum BridgeMessage: Sendable, Equatable {
    case ready(protocolVersion: Int)
    case changed(Snapshot)
    case activeFormats([String])
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
    case openAsset(url: String)
    /// A page link was clicked (with the block to scroll to, for a link to a block).
    case openPage(id: String, block: String?)
    /// Any other link was clicked: the system opens it.
    case openLink(url: String)
    /// Furigana: expects the hiragana reading of `text` as the reply (nil when there is none).
    case suggestReading(text: String)
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
            "content": try record.contentValue()?.foundationObject() ?? NSNull(),
        ]
    }
}

extension BridgeMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, snapshot, active, level, message, context, docId, icon, cover, fileExtension, dataBase64
        case size, id, url, block, text
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "ready": self = .ready(protocolVersion: try c.decode(Int.self, forKey: .protocolVersion))
        case "changed": self = .changed(try c.decode(Snapshot.self, forKey: .snapshot))
        case "activeFormats": self = .activeFormats(try c.decode([String].self, forKey: .active))
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
        case "openAsset": self = .openAsset(url: try c.decode(String.self, forKey: .url))
        case "openPage":
            self = .openPage(id: try c.decode(String.self, forKey: .id), block: try c.decodeIfPresent(String.self, forKey: .block))
        case "openLink": self = .openLink(url: try c.decode(String.self, forKey: .url))
        case "suggestReading": self = .suggestReading(text: try c.decode(String.self, forKey: .text))
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
