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
        try encoder.encode(value)
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

    public var data: Data {
        encoder.data
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

    func container<Key>(keyedBy _: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
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

    fileprivate func encodeData(_ value: Data, lengthPrefix: Bool) {
        if lengthPrefix {
            let length = UInt32(value.count)
            data.append(contentsOf: length.encode(method: .variableWidth))
        }
        data.append(value)
    }

    fileprivate func encodeData(_ value: [UInt8]) {
        let length = UInt32(value.count)
        data.append(contentsOf: length.encode(method: .variableWidth))
        data.append(contentsOf: value)
    }

    fileprivate func encodeArray(_ value: [Encodable]) throws {
        // TODO: be able to figure out the encoding size so we can reserve capacity
        let length = UInt32(value.count)
        data.append(contentsOf: length.encode(method: .variableWidth))
        for item in value {
            try encode(item)
        }
    }

    fileprivate func encodeOptional(_ value: Encodable) throws {
        let mirror = Mirror(reflecting: value)
        if let someValue = mirror.children.first?.value as? Encodable {
            data.append(UInt8(1)) // Encode presence flag
            try encode(someValue) // Encode the unwrapped value
        } else {
            data.append(UInt8(0)) // Encode absence flag
        }
    }

    fileprivate func encode(_ value: some Encodable) throws {
        if let value = value as? Data {
            encodeData(value, lengthPrefix: true)
        } else if let value = value as? [UInt8] {
            encodeData(value)
        } else if let value = value as? any FixedLengthData {
            encodeData(value.data, lengthPrefix: false)
        } else if let value = value as? [Encodable] {
            try encodeArray(value)
        } else if Mirror(reflecting: value).displayStyle == .optional {
            try encodeOptional(value)
        } else {
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
        encoder.encodeData(Data(value.utf8), lengthPrefix: true)
    }

    mutating func encode(_: Double, forKey _: K) throws {
        throw EncodingError.invalidValue(
            Double.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Double is not supported")
        )
    }

    mutating func encode(_: Float, forKey _: K) throws {
        throw EncodingError.invalidValue(
            Float.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Float is not supported")
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
        let uintValue = UInt64(value)
        encoder.encodeInt(uintValue)
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

    mutating func encode(_ value: some Encodable, forKey _: K) throws {
        try encoder.encode(value)
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
            EncodingError.Context(codingPath: codingPath, debugDescription: "Double is not supported")
        )
    }

    mutating func encodeIfPresent(_: Float?, forKey _: K) throws {
        throw EncodingError.invalidValue(
            Float.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Float is not supported")
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

    mutating func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type, forKey key: K) -> KeyedEncodingContainer<NestedKey>
        where NestedKey: CodingKey
    {
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
        encoder.encodeData(Data(value.utf8), lengthPrefix: true)
        count += 1
    }

    mutating func encode(_: Double) throws {
        throw EncodingError.invalidValue(
            Double.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Double is not supported")
        )
    }

    mutating func encode(_: Float) throws {
        throw EncodingError.invalidValue(
            Float.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Float is not supported")
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
        let uintValue = UInt64(value)
        encoder.encodeInt(uintValue)
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
        try encoder.encode(value)
        count += 1
    }

    mutating func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
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
        encoder.encodeData(Data(value.utf8), lengthPrefix: true)
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
        encoder.encodeInt(UInt64(value))
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
            EncodingError.Context(codingPath: codingPath, debugDescription: "Double is not supported")
        )
    }

    mutating func encode(_: Float) throws {
        throw EncodingError.invalidValue(
            Float.self,
            EncodingError.Context(codingPath: codingPath, debugDescription: "Float is not supported")
        )
    }

    mutating func encode(_ value: some Encodable) throws {
        try encoder.encode(value)
    }
}
