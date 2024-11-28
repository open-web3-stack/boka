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

    @Test(arguments: [
        (123, "123"), // Valid integer
        (-456, "-456"), // Negative integer
        (0, "0"), // Zero
    ])
    func integerKeyFromInt(value: Int, expectedString: String) throws {
        let key = JSON.IntegerKey(value)
        #expect(key.intValue == value)
        #expect(key.stringValue == expectedString)
    }

    @Test(arguments: [
        ("123", 123), // Valid string
        ("-456", -456), // Negative integer string
        ("invalid", nil), // Non-numeric string
    ])
    func integerKeyFromString(value: String, expectedInt: Int?) throws {
        let key = JSON.IntegerKey(stringValue: value)
        if let expected = expectedInt {
            #expect(key!.intValue == expected)
            #expect(key!.stringValue == value)
        } else {
            #expect(key == nil) // Ensure `nil` for invalid strings
        }
    }

    @Test(arguments: [
        (123, JSON.number(123.0)), // Integer to JSON
        (-42, JSON.number(-42.0)), // Negative integer to JSON
        (0, JSON.number(0.0)), // Zero to JSON
    ])
    func binaryIntegerToJSON(value: Int, expectedJSON: JSON) throws {
        let json = value.json
        #expect(json == expectedJSON)
    }

    @Test(arguments: [
        ("Hello, world!", JSON.string("Hello, world!")), // Simple string
        ("", JSON.string("")), // Empty string
    ])
    func stringToJSON(value: String, expectedJSON: JSON) throws {
        let json = value.json
        #expect(json == expectedJSON)
    }

    @Test(arguments: [
        (true, JSON.boolean(true)), // Boolean true to JSON
        (false, JSON.boolean(false)), // Boolean false to JSON
    ])
    func boolToJSON(value: Bool, expectedJSON: JSON) throws {
        let json = value.json
        #expect(json == expectedJSON)
    }
}
