import Foundation
import Testing

@testable import Utils

struct JSONTests {
    @Test(arguments: [
        "{\"key\":\"value\"}",
        "[\"a\",1]",
        "\"test\"",
        "42",
        "true",
        "null",
    ])
    func debugDescription(jsonString: String) throws {
        let decoder = JSONDecoder()
        let json = try decoder.decode(JSON.self, from: jsonString.data(using: .utf8)!)
        let debugDescription = json.debugDescription
        let parsedJSON = try decoder.decode(JSON.self, from: debugDescription.data(using: .utf8)!)
        #expect(json == parsedJSON)
    }

    @Test(arguments: [
        ("{\"key\":\"value\"}", JSON.dictionary(["key": .string("value")])),
        ("[\"a\",1]", JSON.array([.string("a"), .number(1)])),
        ("\"test\"", JSON.string("test")),
        ("42", JSON.number(42)),
        ("true", JSON.boolean(true)),
        ("null", JSON.null),
    ])
    func decoding(jsonString: String, expectedJSON: JSON) throws {
        let decoder = JSONDecoder()
        let json = try decoder.decode(JSON.self, from: jsonString.data(using: .utf8)!)
        #expect(json == expectedJSON)
    }

    @Test(arguments: [
        JSON.dictionary(["key": .string("value")]),
        JSON.array([.string("a"), .number(1)]),
        JSON.string("test"),
        JSON.number(42),
        JSON.boolean(true),
        JSON.null,
    ])
    func encoding(json: JSON) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(json)
        let decoder = JSONDecoder()
        let decodedJSON = try decoder.decode(JSON.self, from: data)
        #expect(json == decodedJSON)
    }

    @Test(arguments: [
        JSON.dictionary(["key": .string("value")]),
        JSON.array([.string("a"), .number(1)]),
        JSON.string("test"),
        JSON.number(42),
        JSON.boolean(true),
        JSON.null,
    ])
    func propertyAccess(json: JSON) throws {
        switch json {
        case .dictionary:
            #expect(json.dictionary != nil)
            #expect(json.array == nil)
            #expect(json.string == nil)
            #expect(json.number == nil)
            #expect(json.bool == nil)
        case .array:
            #expect(json.dictionary == nil)
            #expect(json.array != nil)
            #expect(json.string == nil)
            #expect(json.number == nil)
            #expect(json.bool == nil)
        case .string:
            #expect(json.dictionary == nil)
            #expect(json.array == nil)
            #expect(json.string != nil)
            #expect(json.number == nil)
            #expect(json.bool == nil)
        case .number:
            #expect(json.dictionary == nil)
            #expect(json.array == nil)
            #expect(json.string == nil)
            #expect(json.number != nil)
            #expect(json.bool == nil)
        case .boolean:
            #expect(json.dictionary == nil)
            #expect(json.array == nil)
            #expect(json.string == nil)
            #expect(json.number == nil)
            #expect(json.bool != nil)
        case .null:
            #expect(json.dictionary == nil)
            #expect(json.array == nil)
            #expect(json.string == nil)
            #expect(json.number == nil)
            #expect(json.bool == nil)
        }
    }
}
