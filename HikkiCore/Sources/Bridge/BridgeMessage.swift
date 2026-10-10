import Foundation

/// Mirror of editor/src/protocol.ts. Bump both versions together.
public enum BridgeProtocol {
    public static let version = 3
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
