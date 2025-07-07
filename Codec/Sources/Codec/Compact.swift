import Foundation

/// Protocol for types that can be converted to/from UInt for compact encoding
public protocol CompactEncodable {
    /// Convert the value to UInt for encoding
    func toUInt() throws -> UInt

    /// Create an instance from UInt after decoding
    static func fromUInt(_ value: UInt) throws -> Self
}

/// A coding wrapper that converts CompactEncodable types to UInt for compact encoding/decoding.
/// This supports both Swift's built-in integer types and custom types that conform to CompactEncodable.
public struct Compact<T: CompactEncodable & Codable>: Codable, CodableAlias {
    public typealias Alias = T

    public var alias: T

    public init(alias: T) {
        self.alias = alias
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let uintValue = try container.decode(UInt.self)

        do {
            alias = try T.fromUInt(uintValue)
        } catch let error as CompactEncodingError {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Compact decoding failed: \(error.localizedDescription)"
                )
            )
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Value \(uintValue) cannot be converted to \(T.self): \(error)"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        do {
            let uintValue = try alias.toUInt()
            try container.encode(uintValue)
        } catch let error as CompactEncodingError {
            throw EncodingError.invalidValue(
                alias,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Compact encoding failed: \(error.localizedDescription)"
                )
            )
        } catch {
            throw EncodingError.invalidValue(
                alias,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Cannot convert \(alias) to UInt: \(error)"
                )
            )
        }
    }
}

/// Extension to provide default implementation for unsigned integer types
extension UnsignedInteger where Self: CompactEncodable {
    public func toUInt() throws -> UInt {
        guard let result = UInt(exactly: self) else {
            throw CompactEncodingError.valueOutOfRange(value: "\(self)", sourceType: "\(Self.self)", targetType: "UInt")
        }
        return result
    }

    public static func fromUInt(_ value: UInt) throws -> Self {
        guard let result = Self(exactly: value) else {
            throw CompactEncodingError.valueOutOfRange(value: "\(value)", sourceType: "UInt", targetType: "\(Self.self)")
        }
        return result
    }
}

extension UInt8: CompactEncodable {}
extension UInt16: CompactEncodable {}
extension UInt32: CompactEncodable {}
extension UInt64: CompactEncodable {}
extension UInt: CompactEncodable {}

public enum CompactEncodingError: Error, LocalizedError, CustomStringConvertible {
    case valueOutOfRange(value: String, sourceType: String, targetType: String)
    case conversionFailed(value: String, fromType: String, toType: String, reason: String)

    public var description: String {
        switch self {
        case let .valueOutOfRange(value, sourceType, targetType):
            "Value \(value) of type \(sourceType) is out of range for type \(targetType)"
        case let .conversionFailed(value, fromType, toType, reason):
            "Failed to convert value \(value) from \(fromType) to \(toType): \(reason)"
        }
    }

    public var errorDescription: String? {
        description
    }

    public var failureReason: String? {
        switch self {
        case .valueOutOfRange:
            "Value exceeds the range of the target type"
        case .conversionFailed:
            "Type conversion failed during compact encoding/decoding"
        }
    }
}
