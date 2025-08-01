import Codec
import Numerics

public struct SaturatingNumber<T: FixedWidthInteger & Sendable>: Sendable, Hashable {
    public private(set) var value: T

    public static var max: SaturatingNumber {
        SaturatingNumber(T.max)
    }

    public static var min: SaturatingNumber {
        SaturatingNumber(T.min)
    }

    public init(_ value: T) {
        self.value = value
    }

    // Initializer for converting from other integer types to `T` with saturation
    public init(_ value: some FixedWidthInteger & BinaryInteger) {
        self.value = T(clamping: value)
    }

    public static func + (lhs: SaturatingNumber, rhs: SaturatingNumber) -> SaturatingNumber {
        SaturatingNumber(lhs.value.addingWithSaturation(rhs.value))
    }

    public static func - (lhs: SaturatingNumber, rhs: SaturatingNumber) -> SaturatingNumber {
        SaturatingNumber(lhs.value.subtractingWithSaturation(rhs.value))
    }

    public static func * (lhs: SaturatingNumber, rhs: SaturatingNumber) -> SaturatingNumber {
        SaturatingNumber(lhs.value.multipliedWithSaturation(by: rhs.value))
    }

    public static func / (lhs: SaturatingNumber, rhs: SaturatingNumber) -> SaturatingNumber {
        SaturatingNumber(lhs.value / rhs.value)
    }

    public static func % (lhs: SaturatingNumber, rhs: SaturatingNumber) -> SaturatingNumber {
        SaturatingNumber(lhs.value % rhs.value)
    }

    public static prefix func - (lhs: SaturatingNumber) -> SaturatingNumber {
        SaturatingNumber(lhs.value.negatedWithSaturation())
    }

    public static func += (lhs: inout SaturatingNumber, rhs: SaturatingNumber) {
        lhs.value = lhs.value.addingWithSaturation(rhs.value)
    }

    public static func -= (lhs: inout SaturatingNumber, rhs: SaturatingNumber) {
        lhs.value = lhs.value.subtractingWithSaturation(rhs.value)
    }

    public static func *= (lhs: inout SaturatingNumber, rhs: SaturatingNumber) {
        lhs.value = lhs.value.multipliedWithSaturation(by: rhs.value)
    }

    public static func /= (lhs: inout SaturatingNumber, rhs: SaturatingNumber) {
        lhs.value = lhs.value / rhs.value
    }

    public static func %= (lhs: inout SaturatingNumber, rhs: SaturatingNumber) {
        lhs.value = lhs.value % rhs.value
    }

    // With other types

    public static func + (lhs: SaturatingNumber, rhs: T) -> SaturatingNumber {
        SaturatingNumber(lhs.value.addingWithSaturation(rhs))
    }

    public static func - (lhs: SaturatingNumber, rhs: T) -> SaturatingNumber {
        SaturatingNumber(lhs.value.subtractingWithSaturation(rhs))
    }

    public static func * (lhs: SaturatingNumber, rhs: T) -> SaturatingNumber {
        SaturatingNumber(lhs.value.multipliedWithSaturation(by: rhs))
    }

    public static func / (lhs: SaturatingNumber, rhs: T) -> SaturatingNumber {
        SaturatingNumber(lhs.value / rhs)
    }

    public static func % (lhs: SaturatingNumber, rhs: T) -> SaturatingNumber {
        SaturatingNumber(lhs.value % rhs)
    }

    public static func += (lhs: inout SaturatingNumber, rhs: T) {
        lhs.value = lhs.value.addingWithSaturation(rhs)
    }

    public static func -= (lhs: inout SaturatingNumber, rhs: T) {
        lhs.value = lhs.value.subtractingWithSaturation(rhs)
    }

    public static func *= (lhs: inout SaturatingNumber, rhs: T) {
        lhs.value = lhs.value.multipliedWithSaturation(by: rhs)
    }

    public static func /= (lhs: inout SaturatingNumber, rhs: T) {
        lhs.value = lhs.value / rhs
    }

    public static func %= (lhs: inout SaturatingNumber, rhs: T) {
        lhs.value = lhs.value % rhs
    }
}

extension SaturatingNumber: Comparable, Equatable {
    public static func < (lhs: SaturatingNumber, rhs: SaturatingNumber) -> Bool {
        lhs.value < rhs.value
    }

    public static func == (lhs: SaturatingNumber, rhs: SaturatingNumber) -> Bool {
        lhs.value == rhs.value
    }
}

extension SaturatingNumber: CustomStringConvertible {
    public var description: String {
        "\(value)"
    }
}

extension SaturatingNumber: Codable where T: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(T.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension SaturatingNumber: EncodedSize {
    public var encodedSize: Int {
        MemoryLayout<T>.size
    }

    public static var encodeedSizeHint: Int? {
        MemoryLayout<T>.size
    }
}

extension SaturatingNumber: CompactEncodable {
    public func toUInt() throws -> UInt {
        guard let result = UInt(exactly: value) else {
            throw CompactEncodingError.valueOutOfRange(value: "\(value)", sourceType: "\(T.self)", targetType: "UInt")
        }
        return result
    }

    public static func fromUInt(_ value: UInt) throws -> SaturatingNumber<T> {
        guard let converted = T(exactly: value) else {
            throw CompactEncodingError.valueOutOfRange(value: "\(value)", sourceType: "UInt", targetType: "\(T.self)")
        }
        return SaturatingNumber(converted)
    }
}
