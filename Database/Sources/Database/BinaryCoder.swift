import Blockchain
import Foundation
import RocksDBSwift
import Utils

protocol BinaryCodable {
    func encode() throws -> Data
    static func decode(from data: Data) throws -> Self
}

extension Data: BinaryCodable {
    func encode() throws -> Data {
        self
    }

    static func decode(from data: Data) throws -> Data {
        data
    }
}

extension Data32: BinaryCodable {
    func encode() throws -> Data {
        data
    }

    static func decode(from data: Data) throws -> Data32 {
        try Data32(data).unwrap()
    }
}

extension UInt32: BinaryCodable {
    static func decode(from data: Data) throws -> Self {
        guard data.count == 4 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Invalid data length"
                )
            )
        }
        return data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(as: Self.self)
        }
    }
}

extension Set<Data32>: BinaryCodable {
    func encode() throws -> Data {
        var data = Data(capacity: count * 32)
        for element in self {
            data.append(element.data)
        }
        return data
    }

    static func decode(from data: Data) throws -> Set<Element> {
        guard data.count % 32 == 0 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Invalid data length"
                )
            )
        }
        var set = Set<Element>()
        for i in stride(from: 0, to: data.count, by: 32) {
            set.insert(Data32(data[relative: i ..< i + 32])!)
        }
        return set
    }
}

struct BinaryCoder<Key: BinaryCodable, Value: BinaryCodable>: StoreCoder {
    typealias Key = Key
    typealias Value = Value

    private let config: ProtocolConfigRef
    private let prefix: Data?

    init(config: ProtocolConfigRef, prefix: Data? = nil) {
        self.config = config
        self.prefix = prefix
    }

    func encode(key: Key) throws -> Data {
        let encodedKey = try key.encode()
        return prefix.map { $0 + encodedKey } ?? encodedKey
    }

    func encode(value: Value) throws -> Data {
        try value.encode()
    }

    func decode(data: Data) throws -> Value {
        try Value.decode(from: data)
    }
}
