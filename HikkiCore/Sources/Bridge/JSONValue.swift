import Foundation

/// Opaque JSON passed through untouched (Tiptap documents). Swift never interprets the editor schema.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Through a `Decoder` (a value inside a bridge message). The kinds are tried most common first in a Tiptap
    /// document — object, string, array — so most nodes decode on the first or second try (every failed try
    /// builds a `DecodingError`). Whole documents take `init(jsonData:)`, which tries nothing.
    public init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: AnyKey.self) {
            var object: [String: JSONValue] = [:]
            object.reserveCapacity(keyed.allKeys.count)
            for key in keyed.allKeys { object[key.stringValue] = try keyed.decode(JSONValue.self, forKey: key) }
            self = .object(object)
            return
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .bool(try container.decode(Bool.self))
        }
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// A whole document: parsed by `JSONSerialization` and converted, booleans told from numbers by their type.
    public init(jsonData: Data) throws {
        self = Self(foundation: try JSONSerialization.jsonObject(with: jsonData, options: .fragmentsAllowed))
    }

    private init(foundation value: Any) {
        switch value {
        case let string as String: self = .string(string)
        case let object as [String: Any]: self = .object(object.mapValues(JSONValue.init(foundation:)))
        case let array as [Any]: self = .array(array.map(JSONValue.init(foundation:)))
        case let number as NSNumber:
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        default: self = .null
        }
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Foundation representation for `WKWebView.callAsyncJavaScript(arguments:)`.
    public func foundationObject() throws -> Any {
        try JSONSerialization.jsonObject(with: jsonData(), options: .fragmentsAllowed)
    }
}
