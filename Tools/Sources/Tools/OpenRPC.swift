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

// MARK: - Schema Generation Utilities

private protocol OptionalProtocol {
    static var wrappedType: Any.Type { get }
}

extension Optional: OptionalProtocol {
    static var wrappedType: Any.Type {
        Wrapped.self
    }
}

func createSpecContent(type: Any.Type, name: String?) -> SpecContent {
    if let type = type as? OptionalProtocol.Type {
        return createSpecContentInner(type: type.wrappedType, required: false)
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

protocol TypeDescription {
    static var name: String { get }
    static var schema: any JSONSchemaComponent { get }
}

func getName(type: Any.Type) -> String {
    if let type = type as? TypeDescription.Type {
        return type.name
    }
    return String(describing: type)
}

func getSchema(type: Any.Type) -> any JSONSchemaComponent {
    if let type = type as? TypeDescription.Type {
        return type.schema
    }

    let info = try! typeInfo(of: type)
    switch info.kind {
    case .struct, .class:
        return buildObjectSchema(type: type, properties: info.properties)
    default:
        return JSONObject().title(getName(type: type))
    }
}

private func buildObjectSchema(type: Any.Type, properties: [PropertyInfo]) -> any JSONSchemaComponent {
    JSONObject {
        for field in properties {
            JSONProperty(key: field.name) {
                getSchema(type: field.type)
            }
        }
    }
    .title(getName(type: type))
}

// MARK: - Primitive Types Conformance

extension Bool: TypeDescription {
    static var name: String { "Bool" }
    static var schema: any JSONSchemaComponent { JSONBoolean() }
}

extension String: TypeDescription {
    static var name: String { "String" }
    static var schema: any JSONSchemaComponent { JSONString() }
}

// MARK: - Numeric Types Conformance

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

// MARK: - Data Types Conformance

extension Data: TypeDescription {
    static var name: String { "Data" }
    static var schema: any JSONSchemaComponent {
        JSONString()
            .title(name)
            .pattern("^0x[0-9a-fA-F]*$")
    }
}

extension FixedSizeData: TypeDescription {
    static var name: String { "Data\(T.value)" }
    static var schema: any JSONSchemaComponent {
        JSONString()
            .title(name)
            .pattern("^0x[0-9a-fA-F]{\(T.value * 2)}$")
    }
}

// MARK: - Collection Types Conformance

extension Array: TypeDescription {
    static var name: String { "Array<\(getName(type: Element.self))>" }

    static var schema: any JSONSchemaComponent {
        JSONArray {
            getSchema(type: Element.self)
        }
        .title(name)
    }
}

extension Set: TypeDescription {
    static var name: String { "Set<\(getName(type: Element.self))>" }

    static var schema: any JSONSchemaComponent {
        JSONArray {
            getSchema(type: Element.self)
        }
        .title(name)
        .uniqueItems()
    }
}

extension Dictionary: TypeDescription {
    static var name: String {
        "Dictionary<\(getName(type: Key.self)), \(getName(type: Value.self))>"
    }

    static var schema: any JSONSchemaComponent {
        JSONObject()
            .title(name)
            .additionalProperties(getSchema(type: Value.self))
    }
}

// MARK: - Special Array Types Conformance

extension LimitedSizeArray: TypeDescription {
    static var name: String {
        minLength == maxLength
            ? "Array\(minLength)<\(getName(type: T.self))>"
            : "Array<\(getName(type: T.self))>[\(minLength)..<\(maxLength)]"
    }

    static var schema: any JSONSchemaComponent {
        JSONArray {
            getSchema(type: T.self)
        }
        .title(name)
        .minItems(minLength)
        .maxItems(maxLength)
    }
}

extension ConfigLimitedSizeArray: TypeDescription {
    static var name: String {
        "Array<\(getName(type: T.self))>[\(getName(type: TMinLength.self))..<\(getName(type: TMaxLength.self))]"
    }

    static var schema: any JSONSchemaComponent {
        JSONArray {
            getSchema(type: T.self)
        }
        .title(name)
    }
}

// MARK: - Optional and Reference Types Conformance

extension Optional: TypeDescription {
    static var name: String { "Optional<\(getName(type: Wrapped.self))>" }
    static var schema: any JSONSchemaComponent { getSchema(type: Wrapped.self) }
}

extension Ref: TypeDescription {
    static var name: String { getName(type: T.self) }
    static var schema: any JSONSchemaComponent { getSchema(type: T.self) }
}
