import Foundation

public class JamDecoder {
    private var input: DataInput
    private let config: Any?

    public init(data: DataInput, config: Any? = nil) {
        input = data
        self.config = config
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let context = DecodeContext(input: input)
        context.userInfo[.config] = config
        let res = try context.decode(type, key: nil)
        input = context.input
        return res
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: DataInput, withConfig config: Any? = nil) throws -> T {
        let decoder = JamDecoder(data: data, config: config)
        let val = try decoder.decode(type)
        try decoder.finalize()
        return val
    }

    public func finalize() throws {
        guard input.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Not all data was consumed"
                )
            )
        }
    }

    public var isAtEnd: Bool {
        input.isEmpty
    }
}

private protocol ArrayWrapper: Collection where Element: Decodable {
    static func from(array: [Element]) -> Self
}

extension Array: ArrayWrapper where Element: Decodable {
    static func from(array: [Element]) -> Self {
        array
    }
}

private protocol OptionalWrapper: Decodable {
    static var wrappedType: Decodable.Type { get }
}

extension Optional: OptionalWrapper where Wrapped: Decodable {
    static var wrappedType: Decodable.Type {
        Wrapped.self
    }
}

private class DecodeContext: Decoder {
    struct PushCodingPath: ~Copyable {
        let decoder: DecodeContext
        let noop: Bool

        init(decoder: DecodeContext, key: CodingKey?) {
            self.decoder = decoder
            if let key {
                decoder.codingPath.append(key)
                noop = false
            } else {
                noop = true
            }
        }

        deinit {
            if !noop {
                decoder.codingPath.removeLast()
            }
        }
    }

    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]

    var input: DataInput

    init(input: DataInput, codingPath: [CodingKey] = [], userInfo: [CodingUserInfoKey: Any] = [:]) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.input = input
        self.userInfo[.isJamCodec] = true
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

    fileprivate func decodeInt<T: FixedWidthInteger>(codingPath _: @autoclosure () -> [CodingKey]) throws -> T {
        let data = try input.read(length: MemoryLayout<T>.size)
        return data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(as: T.self)
        }
    }

    fileprivate func decodeData(codingPath: @autoclosure () -> [CodingKey]) throws -> Data {
        let length = try input.decodeUInt64()
        // sanity check: length must be less than 4gb
        guard length < 0x1_0000_0000 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath(),
                    debugDescription: "Invalid data length"
                )
            )
        }
        let res = try input.read(length: Int(length))
        return res
    }

    fileprivate func decodeData(codingPath: @autoclosure () -> [CodingKey]) throws -> [UInt8] {
        let length = try input.decodeUInt64()
        // sanity check: length must be less than 4gb
        guard length < 0x1_0000_0000 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath(),
                    debugDescription: "Invalid data length"
                )
            )
        }
        let res = try input.read(length: Int(length))
        return Array(res)
    }

    fileprivate func decodeArray<T: ArrayWrapper>(_ type: T.Type, key: CodingKey?) throws -> T {
        let length = try input.decodeUInt64()
        // sanity check: length can't be unreasonably large
        guard length < 0xFFFFFF else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Invalid array length"
                )
            )
        }
        var array = [T.Element]()
        array.reserveCapacity(Int(length))
        for _ in 0 ..< length {
            try array.append(decode(type.Element.self, key: key))
        }
        return type.from(array: array)
    }

    fileprivate func decodeFixedLengthData<T: FixedLengthData>(_ type: T.Type, key: CodingKey?) throws -> T {
        try withExtendedLifetime(PushCodingPath(decoder: self, key: key)) {
            let length = try type.length(decoder: self)
            let data = try input.read(length: length)
            return try type.init(decoder: self, data: data)
        }
    }

    fileprivate func decodeOptional<T: Decodable>(_ type: T.Type, key: CodingKey?) throws -> T? {
        let byte = try input.read()
        switch byte {
        case 0:
            return nil
        case 1:
            return try decode(type, key: key)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Invalid boolean value: \(byte)"
                )
            )
        }
    }

    fileprivate func decode<T: Decodable>(_ type: T.Type, key: CodingKey?) throws -> T {
        // optional hanlding must be first to avoid type coercion
        if let type = type as? any OptionalWrapper.Type {
            try decodeOptional(type.wrappedType, key: key) as! T
        } else if type == Data.self {
            try decodeData(codingPath: codingPath) as Data as! T
        } else if type == [UInt8].self {
            try decodeData(codingPath: codingPath) as [UInt8] as! T
        } else if let type = type as? any FixedLengthData.Type {
            try decodeFixedLengthData(type, key: key) as! T
        } else if let type = type as? any ArrayWrapper.Type {
            try decodeArray(type, key: key) as! T
        } else {
            try withExtendedLifetime(PushCodingPath(decoder: self, key: key)) {
                try .init(from: self)
            }
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
        !decoder.input.isEmpty
    }

    func decodeNil(forKey _: K) throws -> Bool {
        let byte = try decoder.input.read()
        return byte == 0
    }

    func decode(_: Bool.Type, forKey _: K) throws -> Bool {
        let byte = try decoder.input.read()
        return byte == 1
    }

    func decode(_: String.Type, forKey key: K) throws -> String {
        let data: Data = try decoder.decodeData(codingPath: codingPath + [key])
        guard let string = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid UTF8 string")
        }
        return string
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

    func decode(_: Int8.Type, forKey _: K) throws -> Int8 {
        let byte = try decoder.input.read()
        return Int8(bitPattern: byte)
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

    func decode(_: UInt8.Type, forKey _: K) throws -> UInt8 {
        let byte = try decoder.input.read()
        return byte
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

    func decode<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T {
        try decoder.decode(type, key: key)
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T? {
        let byte = try decoder.input.read()
        switch byte {
        case 0:
            return nil
        case 1:
            return try decoder.decode(type, key: key)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid boolean value: \(byte)"
                )
            )
        }
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
        decoder.input.isEmpty
    }

    var currentIndex: Int = 0

    let decoder: DecodeContext

    mutating func decodeNil() throws -> Bool {
        let byte = try decoder.input.read()
        currentIndex += 1
        return byte == 0
    }

    mutating func decode(_: Bool.Type) throws -> Bool {
        let byte = try decoder.input.read()
        currentIndex += 1
        return byte == 1
    }

    mutating func decode(_: String.Type) throws -> String {
        let data: Data = try decoder.decodeData(codingPath: codingPath)
        guard let value = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: "Invalid UTF8 string")
        }
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
        let byte = try decoder.input.read()
        currentIndex += 1
        return Int8(bitPattern: byte)
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
        let byte = try decoder.input.read()
        currentIndex += 1
        return byte
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

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        defer { currentIndex += 1 }
        return try decoder.decode(type, key: nil)
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
        let byte = try? decoder.input.read()
        return byte == 0
    }

    func decode(_: Bool.Type) throws -> Bool {
        let byte = try decoder.input.read()
        return byte == 1
    }

    func decode(_: String.Type) throws -> String {
        let data: Data = try decoder.decodeData(codingPath: codingPath)
        guard let string = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorruptedError(in: self, debugDescription: "Invalid UTF8 string")
        }
        return string
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
        let byte = try decoder.input.read()
        return Int8(bitPattern: byte)
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
        let byte = try decoder.input.read()
        return byte
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

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try decoder.decode(type, key: nil)
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
