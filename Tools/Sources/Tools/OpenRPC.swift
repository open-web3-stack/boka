import ArgumentParser
import Foundation
import JSONSchema
import JSONSchemaBuilder
import RPC
import Runtime
import Utils

struct OpenRPC: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "OpenRPC tools",
        subcommands: [Generate.self]
    )

    struct Generate: AsyncParsableCommand {
        @Argument(help: "output file")
        var output: String = "openrpc.json"

        func run() async throws {
            let handlers = AllHandlers.handlers

            let spec = SpecDoc(
                openrpc: "1.0.0",
                info: SpecInfo(
                    title: "JAM JSONRPC (draft)",
                    version: "0.0.1",
                    description: "JSONRPC spec for JAM nodes (draft)"
                ),
                methods: handlers.map { h in
                    SpecMethod(
                        name: h.method,
                        summary: h.summary,
                        description: nil,
                        params: h.requestType.types.enumerated().map {
                            createSpecContent(type: $1, name: h.requestNames[safe: $0])
                        },
                        result: createSpecContent(type: h.responseType, name: nil),
                        examples: nil
                    )
                }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(spec)
            try data.write(to: URL(fileURLWithPath: output))
        }
    }
}

// MARK: - Optional Type Check

private protocol OptionalProtocol {
    static var wrappedType: Any.Type { get }
}

extension Optional: OptionalProtocol {
    static var wrappedType: Any.Type {
        Wrapped.self
    }
}

// MARK: - Type Erasure Wrapper

struct AnyJSONSchemaComponent: JSONSchemaComponent, @unchecked Sendable {
    typealias Output = Any

    private var _schemaValue: [KeywordIdentifier: JSONValue]
    private let _parse: @Sendable (JSONValue) -> Parsed<Any, ParseIssue>

    init(wrapped component: some JSONSchemaComponent) {
        _schemaValue = component.schemaValue
        _parse = { value in component.parse(value).map { $0 as Any } }
    }

    var schemaValue: [KeywordIdentifier: JSONValue] {
        get { _schemaValue }
        set {
            _schemaValue = newValue
        }
    }

    func parse(_ value: JSONValue) -> Parsed<Any, ParseIssue> {
        _parse(value)
    }
}

// 👇 Wrap helper for nicer syntax
func wrap(_ schema: any JSONSchemaComponent) -> AnyJSONSchemaComponent {
    .init(wrapped: schema)
}

// MARK: - Builder helpers

func build(@JSONSchemaBuilder _ content: () -> any JSONSchemaComponent) -> any JSONSchemaComponent {
    content()
}

func createSpecContent(type: Any.Type, name: String?) -> SpecContent {
    if let optionalType = type as? OptionalProtocol.Type {
        return createSpecContentInner(type: optionalType.wrappedType, required: false)
    } else {
        return createSpecContentInner(type: type, required: true)
    }

    func createSpecContentInner(type: Any.Type, required: Bool) -> SpecContent {
        .init(
            name: name ?? getName(type: type),
            summary: nil,
            description: nil,
            required: required,
            schema: getSchema(type: type).definition()
        )
    }
}

// MARK: - Type Descriptions

protocol TypeDescription {
    static var name: String { get }
    static var schema: any JSONSchemaComponent { get }
}

func getName(type: Any.Type) -> String {
    if let t = type as? TypeDescription.Type {
        return t.name
    }
    return String(describing: type)
}

func getSchema(type: Any.Type) -> any JSONSchemaComponent {
    if let t = type as? TypeDescription.Type {
        return t.schema
    }

    let info = try! typeInfo(of: type)

    switch info.kind {
    case .struct, .class:
        return build {
            JSONObject {
                for field in info.properties {
                    JSONProperty(key: field.name) {
                        wrap(getSchema(type: field.type))
                    }
                }
            }.title(getName(type: type))
        }
    default:
        return build {
            JSONObject().title(getName(type: type))
        }
    }
}

// MARK: - Conformances

extension Optional: TypeDescription {
    static var name: String {
        "Optional<\(getName(type: Wrapped.self))>"
    }

    static var schema: any JSONSchemaComponent {
        getSchema(type: Wrapped.self)
    }
}

extension Bool: TypeDescription {
    static var name: String { "Bool" }
    static var schema: any JSONSchemaComponent { JSONBoolean() }
}

extension String: TypeDescription {
    static var name: String { "String" }
    static var schema: any JSONSchemaComponent { JSONString() }
}

extension BinaryInteger where Self: TypeDescription {
    static var name: String { String(describing: Self.self) }
    static var schema: any JSONSchemaComponent { JSONInteger() }
}

extension Int8: TypeDescription {}
extension Int16: TypeDescription {}
extension Int32: TypeDescription {}
extension Int64: TypeDescription {}
extension Int: TypeDescription {}
extension UInt8: TypeDescription {}
extension UInt16: TypeDescription {}
extension UInt32: TypeDescription {}
extension UInt64: TypeDescription {}
extension UInt: TypeDescription {}

extension Data: TypeDescription {
    static var name: String { "Data" }
    static var schema: any JSONSchemaComponent {
        JSONString().title(name).pattern("^0x[0-9a-fA-F]*$")
    }
}

extension FixedSizeData: TypeDescription {
    static var name: String { "Data\(T.value)" }
    static var schema: any JSONSchemaComponent {
        JSONString().title(name).pattern("^0x[0-9a-fA-F]{\(T.value * 2)}$")
    }
}

extension Array: TypeDescription {
    static var name: String { "Array<\(getName(type: Element.self))>" }
    static var schema: any JSONSchemaComponent {
        JSONArray { wrap(getSchema(type: Element.self)) }
    }
}

extension Dictionary: TypeDescription {
    static var name: String {
        "Dictionary<\(getName(type: Key.self)), \(getName(type: Value.self))>"
    }

    static var schema: any JSONSchemaComponent {
        JSONObject().title(name)
    }
}

extension Set: TypeDescription {
    static var name: String {
        "Set<\(getName(type: Element.self))>"
    }

    static var schema: any JSONSchemaComponent {
        JSONArray { wrap(getSchema(type: Element.self)) }
    }
}

extension LimitedSizeArray: TypeDescription {
    static var name: String {
        if minLength == maxLength {
            "Array\(minLength)<\(getName(type: T.self))>"
        } else {
            "Array<\(getName(type: T.self))>[\(minLength) ..< \(maxLength)]"
        }
    }

    static var schema: any JSONSchemaComponent {
        JSONArray { wrap(getSchema(type: T.self)) }
    }
}

extension ConfigLimitedSizeArray: TypeDescription {
    static var name: String {
        "Array<\(getName(type: T.self))>[\(getName(type: TMinLength.self)) ..< \(getName(type: TMaxLength.self))]"
    }

    static var schema: any JSONSchemaComponent {
        JSONArray { wrap(getSchema(type: T.self)) }
    }
}

extension Ref: TypeDescription {
    static var name: String { getName(type: T.self) }
    static var schema: any JSONSchemaComponent {
        getSchema(type: T.self)
    }
}
