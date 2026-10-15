import Foundation
import Testing

@testable import HikkiCore

struct JSONValueTests {
    private let sample = #"""
        {"type":"doc","flag":true,"off":false,"int":1,"real":1.5,"neg":-2e3,"nothing":null,"text":"Café 路线图 🎉 \"q\"",
         "content":[{"type":"paragraph","attrs":{"id":"p1","level":2},"content":[{"type":"text","text":"x"}]},[],{},"s",0]}
        """#

    private var expected: JSONValue {
        .object([
            "type": .string("doc"), "flag": .bool(true), "off": .bool(false), "int": .number(1), "real": .number(1.5),
            "neg": .number(-2000), "nothing": .null, "text": .string("Café 路线图 🎉 \"q\""),
            "content": .array([
                .object([
                    "type": .string("paragraph"), "attrs": .object(["id": .string("p1"), "level": .number(2)]),
                    "content": .array([.object(["type": .string("text"), "text": .string("x")])]),
                ]),
                .array([]), .object([:]), .string("s"), .number(0),
            ]),
        ])
    }

    @Test func parsesADocumentKeepingBooleansApartFromNumbers() throws {
        #expect(try JSONValue(jsonData: Data(sample.utf8)) == expected)
    }

    @Test func decodesTheSameThroughADecoder() throws {
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(sample.utf8)) == expected)
        // Inside another Codable value, as bridge messages carry it.
        struct Wrapper: Codable, Equatable { var value: JSONValue }
        let wrapped = try JSONDecoder().decode(Wrapper.self, from: Data(#"{"value":[true,1,1.5,"t",null]}"#.utf8))
        #expect(wrapped.value == .array([.bool(true), .number(1), .number(1.5), .string("t"), .null]))
    }

    @Test func roundTrips() throws {
        let value = expected
        #expect(try JSONValue(jsonData: value.jsonData()) == value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: value.jsonData()) == value)
        for fragment in ["true", "1", "1.5", "\"ü\"", "null"] {
            let parsed = try JSONValue(jsonData: Data(fragment.utf8))
            #expect(try JSONValue(jsonData: parsed.jsonData()) == parsed)
        }
        #expect(try JSONValue(jsonData: Data("true".utf8)) == .bool(true))
        #expect(try JSONValue(jsonData: Data("1".utf8)) == .number(1))
    }

    @Test func rejectsWhatIsNotJSON() {
        #expect(throws: (any Error).self) { try JSONValue(jsonData: Data("{nope".utf8)) }
    }
}
