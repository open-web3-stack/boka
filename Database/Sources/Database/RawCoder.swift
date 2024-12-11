import Foundation
import RocksDBSwift

struct RawCoder: StoreCoder {
    typealias Key = Data
    typealias Value = Data

    func encode(key: Key) throws -> Data {
        key
    }

    func encode(value: Value) throws -> Data {
        value
    }

    func decode(data: Data) throws -> Value {
        data
    }
}
