import Foundation

public class JamDecoder {
    func decode<T: Decodable>(_: T.Type, from data: Data) throws -> T {
        let context = DecodeContext(data: data)
        return try context.decode(codingPath: [])
    }
}

private class DecodeContext: Decoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]

    var data: Data

    init(data: Data, codingPath: [CodingKey] = [], userInfo: [CodingUserInfoKey: Any] = [:]) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.data = data
    }

    func container<Key>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        KeyedDecodingContainer(JamKeyedDecodingContainer<Key>(codingPath: codingPath, decoder: self))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        JamUnkeyedDecodingContainer(codingPath: codingPath, decoder: self)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        JamSingleValueDecodingContainer(codingPath: codingPath, decoder: self)
    }

    fileprivate func decodeInt<T: FixedWidthInteger>(codingPath: [CodingKey]) throws -> T {
        guard data.count >= MemoryLayout<T>.size else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Not enough data to decode \(T.self)"
                )
            )
        }
        let res = data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(as: T.self)
        }
        data.removeFirst(MemoryLayout<T>.size)
        return res
    }

    fileprivate func decodeData(codingPath: [CodingKey]) throws -> Data {
        guard let length = data.decode() else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Unable to decode data length"
                )
            )
        }
        guard data.count >= Int(length) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Not enough data to decode"
                )
            )
        }
        let res = data[data.startIndex ..< data.startIndex + Int(length)]
        data.removeFirst(Int(length))
        return res
    }

    fileprivate func decodeData(codingPath: [CodingKey]) throws -> [UInt8] {
        guard let length = data.decode() else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Unable to decode data length"
                )
            )
        }
        guard data.count >= Int(length) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Not enough data to decode"
                )
            )
        }
        let res = Array(data[data.startIndex ..< data.startIndex + Int(length)])
        data.removeFirst(Int(length))
        return res
    }

    fileprivate func decodeArray<T: Decodable>(codingPath: [CodingKey]) throws -> [T] {
        guard let length = data.decode() else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Unable to decode array length"
                )
            )
        }
        var array: [T] = []
        array.reserveCapacity(Int(length))
        for _ in 0 ..< length {
            try array.append(decode(codingPath: codingPath))
        }
        return array
    }

    fileprivate func decode<T: Decodable>(codingPath: [CodingKey]) throws -> T {
        if T.self == Data.self {
            try decodeData(codingPath: codingPath) as Data as! T
        } else if T.self == [UInt8].self {
            try decodeData(codingPath: codingPath) as [UInt8] as! T
        } else {
            try .init(from: DecodeContext(data: data, codingPath: codingPath, userInfo: userInfo))
        }
    }
}

private struct JamKeyedDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    var codingPath: [CodingKey] = []
    let decoder: DecodeContext
    let allKeys: [K] = []

    init(codingPath: [CodingKey], decoder: DecodeContext) {
        self.codingPath = codingPath
        self.decoder = decoder
    }

    func contains(_: K) -> Bool {
        decoder.data.count > 0
    }

    func decodeNil(forKey key: K) throws -> Bool {
        guard let byte = decoder.data.first else {
            throw DecodingError.keyNotFound(
                key, DecodingError.Context(codingPath: codingPath, debugDescription: "Unexpected end of data")
            )
        }
        return byte == 0
    }

    func decode(_: Bool.Type, forKey key: K) throws -> Bool {
        guard let byte = decoder.data.first else {
            throw DecodingError.keyNotFound(
                key, DecodingError.Context(codingPath: codingPath, debugDescription: "Unexpected end of data")
            )
        }
        return byte == 1
    }

    func decode(_: String.Type, forKey key: K) throws -> String {
        let newCodingPath = codingPath + [key]
        let data: Data = try decoder.decodeData(codingPath: newCodingPath)
        return String(decoding: data, as: UTF8.self)
    }

    func decode(_: Double.Type, forKey key: K) throws -> Double {
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Double not supported")
    }

    func decode(_: Float.Type, forKey key: K) throws -> Float {
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Float not supported")
    }

    func decode(_: Int.Type, forKey key: K) throws -> Int {
        guard let value = try Int(exactly: decode(Int64.self, forKey: key)) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Int out of range")
        }
        return value
    }

    func decode(_: Int8.Type, forKey key: K) throws -> Int8 {
        guard let value = decoder.data.first else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Unexpected end of data"))
        }
        decoder.data.removeFirst(1)
        return Int8(bitPattern: value)
    }

    func decode(_: Int16.Type, forKey key: K) throws -> Int16 {
        try decoder.decodeInt(codingPath: codingPath + [key])
    }

    func decode(_: Int32.Type, forKey key: K) throws -> Int32 {
        try decoder.decodeInt(codingPath: codingPath + [key])
    }

    func decode(_: Int64.Type, forKey key: K) throws -> Int64 {
        try decoder.decodeInt(codingPath: codingPath + [key])
    }

    func decode(_: UInt.Type, forKey key: K) throws -> UInt {
        guard let value = try UInt(exactly: decode(UInt64.self, forKey: key)) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "UInt out of range")
        }
        return value
    }

    func decode(_: UInt8.Type, forKey key: K) throws -> UInt8 {
        guard let value = decoder.data.first else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Unexpected end of data"))
        }
        decoder.data.removeFirst(1)
        return value
    }

    func decode(_: UInt16.Type, forKey key: K) throws -> UInt16 {
        try decoder.decodeInt(codingPath: codingPath + [key])
    }

    func decode(_: UInt32.Type, forKey key: K) throws -> UInt32 {
        try decoder.decodeInt(codingPath: codingPath + [key])
    }

    func decode(_: UInt64.Type, forKey key: K) throws -> UInt64 {
        try decoder.decodeInt(codingPath: codingPath + [key])
    }

    func decode<T: Decodable>(_: T.Type, forKey key: K) throws -> T {
        try decoder.decode(codingPath: codingPath + [key])
    }

    func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type, forKey _: K) throws -> KeyedDecodingContainer<NestedKey>
        where NestedKey: CodingKey
    {
        KeyedDecodingContainer(JamKeyedDecodingContainer<NestedKey>(codingPath: codingPath, decoder: decoder))
    }

    func nestedUnkeyedContainer(forKey _: K) throws -> UnkeyedDecodingContainer {
        JamUnkeyedDecodingContainer(codingPath: codingPath, decoder: decoder)
    }

    func superDecoder() throws -> Decoder {
        decoder
    }

    func superDecoder(forKey _: K) throws -> Decoder {
        decoder
    }
}

private struct JamUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    var codingPath: [CodingKey] = []
    let count: Int? = nil
    var isAtEnd: Bool {
        decoder.data.count == 0
    }

    var currentIndex: Int = 0

    let decoder: DecodeContext

    mutating func decodeNil() throws -> Bool {
        currentIndex += 1
        return decoder.data.count > 0
    }

    mutating func decode(_: Bool.Type) throws -> Bool {
        guard let byte = decoder.data.first else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: "Unexpected end of data")
        }
        currentIndex += 1
        return byte == 1
    }

    mutating func decode(_: String.Type) throws -> String {
        let data: Data = try decoder.decodeData(codingPath: codingPath)
        let value = String(decoding: data, as: UTF8.self)
        currentIndex += 1
        return value
    }

    mutating func decode(_: Double.Type) throws -> Double {
        throw DecodingError.dataCorruptedError(in: self, debugDescription: "Double not supported")
    }

    mutating func decode(_: Float.Type) throws -> Float {
        throw DecodingError.dataCorruptedError(in: self, debugDescription: "Float not supported")
    }

    mutating func decode(_: Int.Type) throws -> Int {
        guard let value = try Int(exactly: decode(Int64.self)) else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: "Int out of range")
        }
        currentIndex += 1
        return value
    }

    mutating func decode(_: Int8.Type) throws -> Int8 {
        guard let value = decoder.data.first else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: "Unexpected end of data")
        }
        decoder.data.removeFirst(1)
        currentIndex += 1
        return Int8(bitPattern: value)
    }

    mutating func decode(_: Int16.Type) throws -> Int16 {
        defer { currentIndex += 1 }
        return try decoder.decodeInt(codingPath: codingPath)
    }

    mutating func decode(_: Int32.Type) throws -> Int32 {
        defer { currentIndex += 1 }
        return try decoder.decodeInt(codingPath: codingPath)
    }

    mutating func decode(_: Int64.Type) throws -> Int64 {
        defer { currentIndex += 1 }
        return try decoder.decodeInt(codingPath: codingPath)
    }

    mutating func decode(_: UInt.Type) throws -> UInt {
        guard let value = try UInt(exactly: decode(UInt64.self)) else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: "UInt out of range")
        }
        currentIndex += 1
        return value
    }

    mutating func decode(_: UInt8.Type) throws -> UInt8 {
        guard let value = decoder.data.first else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: "Unexpected end of data")
        }
        decoder.data.removeFirst(1)
        currentIndex += 1
        return value
    }

    mutating func decode(_: UInt16.Type) throws -> UInt16 {
        defer { currentIndex += 1 }
        return try decoder.decodeInt(codingPath: codingPath)
    }

    mutating func decode(_: UInt32.Type) throws -> UInt32 {
        defer { currentIndex += 1 }
        return try decoder.decodeInt(codingPath: codingPath)
    }

    mutating func decode(_: UInt64.Type) throws -> UInt64 {
        defer { currentIndex += 1 }
        return try decoder.decodeInt(codingPath: codingPath)
    }

    mutating func decode<T: Decodable>(_: T.Type) throws -> T {
        defer { currentIndex += 1 }
        return try decoder.decode(codingPath: codingPath)
    }

    mutating func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey>
        where NestedKey: CodingKey
    {
        KeyedDecodingContainer(JamKeyedDecodingContainer<NestedKey>(codingPath: codingPath, decoder: decoder))
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        JamUnkeyedDecodingContainer(codingPath: codingPath, decoder: decoder)
    }

    mutating func superDecoder() throws -> Decoder {
        decoder
    }
}

private struct JamSingleValueDecodingContainer: SingleValueDecodingContainer {
    var codingPath: [CodingKey] = []

    let decoder: DecodeContext

    func decodeNil() -> Bool {
        decoder.data.count > 0
    }

    func decode(_: Bool.Type) throws -> Bool {
        guard let byte = decoder.data.first else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: "Unexpected end of data")
        }
        decoder.data.removeFirst(1)
        return byte == 1
    }

    func decode(_: String.Type) throws -> String {
        let data: Data = try decoder.decodeData(codingPath: codingPath)
        return String(decoding: data, as: UTF8.self)
    }

    func decode(_: Double.Type) throws -> Double {
        throw DecodingError.dataCorruptedError(in: self, debugDescription: "Double not supported")
    }

    func decode(_: Float.Type) throws -> Float {
        throw DecodingError.dataCorruptedError(in: self, debugDescription: "Float not supported")
    }

    func decode(_: Int.Type) throws -> Int {
        guard let value = try Int(exactly: decode(Int64.self)) else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: "Int out of range")
        }
        return value
    }

    func decode(_: Int8.Type) throws -> Int8 {
        guard let value = decoder.data.first else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: "Unexpected end of data")
        }
        decoder.data.removeFirst(1)
        return Int8(bitPattern: value)
    }

    func decode(_: Int16.Type) throws -> Int16 {
        try decoder.decodeInt(codingPath: codingPath)
    }

    func decode(_: Int32.Type) throws -> Int32 {
        try decoder.decodeInt(codingPath: codingPath)
    }

    func decode(_: Int64.Type) throws -> Int64 {
        try decoder.decodeInt(codingPath: codingPath)
    }

    func decode(_: UInt.Type) throws -> UInt {
        guard let value = try UInt(exactly: decode(UInt64.self)) else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: "UInt out of range")
        }
        return value
    }

    func decode(_: UInt8.Type) throws -> UInt8 {
        guard let value = decoder.data.first else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: "Unexpected end of data")
        }
        decoder.data.removeFirst(1)
        return value
    }

    func decode(_: UInt16.Type) throws -> UInt16 {
        try decoder.decodeInt(codingPath: codingPath)
    }

    func decode(_: UInt32.Type) throws -> UInt32 {
        try decoder.decodeInt(codingPath: codingPath)
    }

    func decode(_: UInt64.Type) throws -> UInt64 {
        try decoder.decodeInt(codingPath: codingPath)
    }

    func decode<T: Decodable>(_: T.Type) throws -> T {
        try decoder.decode(codingPath: codingPath)
    }

    func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey>
        where NestedKey: CodingKey
    {
        KeyedDecodingContainer(JamKeyedDecodingContainer<NestedKey>(codingPath: codingPath, decoder: decoder))
    }

    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        JamUnkeyedDecodingContainer(codingPath: codingPath, decoder: decoder)
    }

    func superDecoder() throws -> Decoder {
        decoder
    }
}
