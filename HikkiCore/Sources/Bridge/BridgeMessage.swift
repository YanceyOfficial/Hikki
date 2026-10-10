import Foundation

/// Mirror of editor/src/protocol.ts. Bump both versions together.
public enum BridgeProtocol {
    public static let version = 1
}

public struct Snapshot: Codable, Sendable, Equatable {
    public var docId: String
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
}

public enum BridgeError: Error, Equatable {
    case notJSON
    case unknownType(String)
}

extension BridgeMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, snapshot, active, level, message, context
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
