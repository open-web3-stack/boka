import Foundation

public class JamEncoder {
    private let encoder: EncodeContext

    public init(_ data: Data = Data()) {
        encoder = EncodeContext(data)
    }

    public init(capacity: Int) {
        encoder = EncodeContext(Data(capacity: capacity))
    }

    public func encode(_ value: any Encodable) throws {
        try encoder.encode(value, key: nil)
    }

    public static func encode(_ value: any Encodable) throws -> Data {
        let encoder = if let value = value as? EncodedSize {
            JamEncoder(capacity: value.encodedSize)
        } else {
            JamEncoder()
        }
        try encoder.encode(value)
        return encoder.data
    }

    public static func encode(_ values: any Encodable...) throws -> Data {
        let encoder = JamEncoder()
        for value in values {
            try encoder.encode(value)
        }
        return encoder.data
    }

    public var data: Data {
        encoder.data
    }
}

private protocol OptionalWrapper: Encodable {
    var wrapped: Encodable? { get }
}

extension Optional: OptionalWrapper where Wrapped: Encodable {
    var wrapped: Encodable? {
        self
    }
}

private class EncodeContext: Encoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [
        .isJamCodec: true,
    ]

    var data: Data

    init(_ data: Data) {
        self.data = data
    }

    func container<Key: CodingKey>(keyedBy _: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(JamKeyedEncodingContainer<Key>(codingPath: codingPath, encoder: self))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        JamUnkeyedEncodingContainer(codingPath: codingPath, encoder: self)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        JamSingleValueEncodingContainer(codingPath: codingPath, encoder: self)
    }

    fileprivate func encodeInt<T: FixedWidthInteger>(_ value: T) {
        withUnsafePointer(to: value) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<T>.size) {
                self.data.append($0, count: MemoryLayout<T>.size)
            }
        }
    }

    fileprivate func encodeCompact(_ value: some UnsignedInteger) {
        data.append(contentsOf: value.encode(method: .variableWidth))
    }

    fileprivate func encodeData(_ value: Data, codingPath: [CodingKey]) {
        let lengthPrefix = !codingPath.isEmpty
        if lengthPrefix {
            let length = UInt32(value.count)
            data.append(contentsOf: length.encode(method: .variableWidth))
        }
        data.append(value)
    }

    fileprivate func encodeData(_ value: [UInt8], codingPath: [CodingKey]) {
        let lengthPrefix = !codingPath.isEmpty
        if lengthPrefix {
            let length = UInt32(value.count)
            data.append(contentsOf: length.encode(method: .variableWidth))
        }
        data.append(contentsOf: value)
    }

    fileprivate func encodeArray(_ value: [Encodable], key: CodingKey?) throws {
        // TODO: be able to figure out the encoding size so we can reserve capacity
        let length = UInt32(value.count)
        data.append(contentsOf: length.encode(method: .variableWidth))
        for item in value {
            try encode(item, key: key)
        }
    }

    fileprivate func encodeOptional(_ value: OptionalWrapper, key: CodingKey?) throws {
        if let value = value.wrapped {
            data.append(UInt8(1)) // Encode presence flag
            try encode(value, key: key)
        } else {
            if key == nil, codingPath.isEmpty {
                // top-level nil encoding: do nothing (empty data)
                return
            } else {
                data.append(UInt8(0)) // Encode absence flag
            }
        }
    }

    fileprivate func encode(_ value: some Encodable, key: CodingKey? = nil) throws {
        // optional handling must be first to avoid type coercion
        if let value = value as? OptionalWrapper {
            try encodeOptional(value, key: key)
        } else if let value = value as? Data {
            encodeData(value, codingPath: codingPath)
        } else if type(of: value) == [UInt8].self || type(of: value) == Array<UInt8>.self {
            encodeData(value as! [UInt8], codingPath: codingPath)
        } else if let value = value as? any FixedLengthData {
            data.append(value.data)
        } else if let value = value as? [Encodable] {
            try encodeArray(value, key: key)
        } else {
            let oldPath = codingPath
            codingPath.append(key ?? DefaultKey(for: type(of: value)))
            defer { codingPath = oldPath }
            try value.encode(to: self)
        }
    }
}

private struct JamKeyedEncodingContainer<K: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [CodingKey] = []

    let encoder: EncodeContext

    mutating func encodeNil(forKey _: K) throws {
        encoder.data.append(0)
    }

    mutating func encode(_ value: Bool, forKey _: K) throws {
        encoder.data.append(value ? 1 : 0)
    }

    mutating func encode(_ value: String, forKey _: K) throws {
        encoder.encodeData(Data(value.utf8), codingPath: encoder.codingPath)
    }

    mutating func encode(_: Double, forKey _: K) throws {
        throw EncodingError.invalidValue(
            Double.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Double is not supported"),
        )
    }

    mutating func encode(_: Float, forKey _: K) throws {
        throw EncodingError.invalidValue(
            Float.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Float is not supported"),
        )
    }

    mutating func encode(_ value: Int, forKey _: K) throws {
        let intValue = Int64(value)
        encoder.encodeInt(intValue)
    }

    mutating func encode(_ value: Int8, forKey _: K) throws {
        encoder.data.append(UInt8(bitPattern: value))
    }

    mutating func encode(_ value: Int16, forKey _: K) throws {
        encoder.encodeInt(value)
    }

    mutating func encode(_ value: Int32, forKey _: K) throws {
        encoder.encodeInt(value)
    }

    mutating func encode(_ value: Int64, forKey _: K) throws {
        encoder.encodeInt(value)
    }

    mutating func encode(_ value: UInt, forKey _: K) throws {
        encoder.encodeCompact(value)
    }

    mutating func encode(_ value: UInt8, forKey _: K) throws {
        encoder.data.append(value)
    }

    mutating func encode(_ value: UInt16, forKey _: K) throws {
        encoder.encodeInt(value)
    }

    mutating func encode(_ value: UInt32, forKey _: K) throws {
        encoder.encodeInt(value)
    }

    mutating func encode(_ value: UInt64, forKey _: K) throws {
        encoder.encodeInt(value)
    }

    mutating func encode(_ value: some Encodable, forKey key: K) throws {
        try encoder.encode(value, key: key)
    }

    mutating func encodeIfPresent(_ value: Bool?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func encodeIfPresent(_ value: String?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func encodeIfPresent(_: Double?, forKey _: K) throws {
        throw EncodingError.invalidValue(
            Double.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Double is not supported"),
        )
    }

    mutating func encodeIfPresent(_: Float?, forKey _: K) throws {
        throw EncodingError.invalidValue(
            Float.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Float is not supported"),
        )
    }

    mutating func encodeIfPresent(_ value: Int?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func encodeIfPresent(_ value: Int8?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func encodeIfPresent(_ value: Int16?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func encodeIfPresent(_ value: Int32?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func encodeIfPresent(_ value: Int64?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func encodeIfPresent(_ value: UInt?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func encodeIfPresent(_ value: UInt8?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func encodeIfPresent(_ value: UInt16?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func encodeIfPresent(_ value: UInt32?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func encodeIfPresent(_ value: UInt64?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func encodeIfPresent(_ value: (some Encodable)?, forKey key: K) throws {
        if let value {
            encoder.data.append(1)
            try encode(value, forKey: key)
        } else {
            encoder.data.append(0)
        }
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy _: NestedKey.Type, forKey key: K) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(JamKeyedEncodingContainer<NestedKey>(codingPath: codingPath + [key], encoder: encoder))
    }

    mutating func nestedUnkeyedContainer(forKey key: K) -> UnkeyedEncodingContainer {
        JamUnkeyedEncodingContainer(codingPath: codingPath + [key], encoder: encoder)
    }

    mutating func superEncoder() -> Encoder {
        encoder
    }

    mutating func superEncoder(forKey _: K) -> Encoder {
        encoder
    }
}

private struct JamUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    var codingPath: [CodingKey] = []
    var count: Int = 0

    let encoder: EncodeContext

    mutating func encodeNil() throws {
        encoder.data.append(0)
        count += 1
    }

    mutating func encode(_ value: Bool) throws {
        encoder.data.append(value ? 1 : 0)
        count += 1
    }

    mutating func encode(_ value: String) throws {
        encoder.encodeData(Data(value.utf8), codingPath: encoder.codingPath)
        count += 1
    }

    mutating func encode(_: Double) throws {
        throw EncodingError.invalidValue(
            Double.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Double is not supported"),
        )
    }

    mutating func encode(_: Float) throws {
        throw EncodingError.invalidValue(
            Float.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Float is not supported"),
        )
    }

    mutating func encode(_ value: Int) throws {
        let intValue = Int64(value)
        encoder.encodeInt(intValue)
        count += 1
    }

    mutating func encode(_ value: Int8) throws {
        encoder.data.append(UInt8(bitPattern: value))
        count += 1
    }

    mutating func encode(_ value: Int16) throws {
        encoder.encodeInt(value)
        count += 1
    }

    mutating func encode(_ value: Int32) throws {
        encoder.encodeInt(value)
        count += 1
    }

    mutating func encode(_ value: Int64) throws {
        encoder.encodeInt(value)
        count += 1
    }

    mutating func encode(_ value: UInt) throws {
        encoder.encodeCompact(value)
        count += 1
    }

    mutating func encode(_ value: UInt8) throws {
        encoder.data.append(value)
        count += 1
    }

    mutating func encode(_ value: UInt16) throws {
        encoder.encodeInt(value)
        count += 1
    }

    mutating func encode(_ value: UInt32) throws {
        encoder.encodeInt(value)
        count += 1
    }

    mutating func encode(_ value: UInt64) throws {
        encoder.encodeInt(value)
        count += 1
    }

    mutating func encode(_ value: some Encodable) throws {
        try encoder.encode(value, key: nil)
        count += 1
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy _: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(JamKeyedEncodingContainer<NestedKey>(codingPath: codingPath, encoder: encoder))
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        JamUnkeyedEncodingContainer(codingPath: codingPath, encoder: encoder)
    }

    mutating func superEncoder() -> Encoder {
        encoder
    }
}

private struct JamSingleValueEncodingContainer: SingleValueEncodingContainer {
    var codingPath: [CodingKey] = []

    let encoder: EncodeContext

    mutating func encodeNil() throws {
        encoder.data.append(0)
    }

    mutating func encode(_ value: Bool) throws {
        encoder.data.append(value ? 1 : 0)
    }

    mutating func encode(_ value: String) throws {
        encoder.encodeData(Data(value.utf8), codingPath: encoder.codingPath)
    }

    mutating func encode(_ value: Int) throws {
        encoder.encodeInt(Int64(value))
    }

    mutating func encode(_ value: Int8) throws {
        encoder.data.append(UInt8(bitPattern: value))
    }

    mutating func encode(_ value: Int16) throws {
        encoder.encodeInt(value)
    }

    mutating func encode(_ value: Int32) throws {
        encoder.encodeInt(value)
    }

    mutating func encode(_ value: Int64) throws {
        encoder.encodeInt(value)
    }

    mutating func encode(_ value: UInt) throws {
        encoder.encodeCompact(value)
    }

    mutating func encode(_ value: UInt8) throws {
        encoder.data.append(value)
    }

    mutating func encode(_ value: UInt16) throws {
        encoder.encodeInt(value)
    }

    mutating func encode(_ value: UInt32) throws {
        encoder.encodeInt(value)
    }

    mutating func encode(_ value: UInt64) throws {
        encoder.encodeInt(value)
    }

    mutating func encode(_: Double) throws {
        throw EncodingError.invalidValue(
            Double.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Double is not supported"),
        )
    }

    mutating func encode(_: Float) throws {
        throw EncodingError.invalidValue(
            Float.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Float is not supported"),
        )
    }

    mutating func encode(_ value: some Encodable) throws {
        try encoder.encode(value, key: nil)
    }
}
