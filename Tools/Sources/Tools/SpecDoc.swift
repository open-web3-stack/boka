import JSONSchema
import Utils

struct SpecInfo: Codable {
    var title: String
    var version: String
    var description: String?
}

struct SpecMethod: Codable {
    var name: String
    var summary: String?
    var description: String?
    var params: [SpecContent]?
    var result: SpecContent
    var examples: [SpecExample]?
}

struct SpecContent: Codable {
    var name: String
    var summary: String?
    var description: String?
    var required: Bool?
    var schema: Schema
}

struct SpecExample: Codable {
    var name: String
    var summary: String?
    var description: String?
    var params: [SpecExampleParam]
    var result: SpecExampleResult?
}

struct SpecExampleParam: Codable {
    var name: String
    var value: JSON
}

struct SpecExampleResult: Codable {
    var name: String
    var value: JSON
}

struct SpecDoc: Codable {
    var openrpc: String = "1.0.0"
    var info: SpecInfo
    var methods: [SpecMethod]
}
