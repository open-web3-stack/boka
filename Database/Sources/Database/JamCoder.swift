import Blockchain
import Codec
import Foundation
import RocksDBSwift

struct JamCoder<Key: Encodable, Value: Codable>: StoreCoder {
    typealias Key = Key
    typealias Value = Value

    private let config: ProtocolConfigRef
    private let prefix: Data

    init(config: ProtocolConfigRef, prefix: Data = Data()) {
        self.config = config
        self.prefix = prefix
    }

    func encode(key: Key) throws -> Data {
        let encoder = JamEncoder(prefix)
        try encoder.encode(key)
        return encoder.data
    }

    func encode(value: Value) throws -> Data {
        try JamEncoder.encode(value)
    }

    func decode(data: Data) throws -> Value {
        try JamDecoder.decode(Value.self, from: data, withConfig: config)
    }
}
