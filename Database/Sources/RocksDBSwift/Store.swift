import Foundation

public protocol StoreCoder<Key, Value>: Sendable {
    associatedtype Key: Encodable
    associatedtype Value: Decodable

    func encode(key: Key) throws -> Data
    func decode(data: Data) throws -> Value
}

public final class Store<CFKey: ColumnFamilyKey, Coder: StoreCoder>: Sendable {
    private let db: RocksDB<CFKey>
    private let column: CFKey
    private let coder: Coder

    public init(db: RocksDB<CFKey>, column: CFKey, coder: Coder) {
        self.db = db
        self.column = column
        self.coder = coder
    }

    public func get(key: Coder.Key) throws -> Coder.Value? {
        let encodedKey = try coder.encode(key: key)

        let data = try db.get(column: column, key: encodedKey)

        return try data.map { try coder.decode(data: $0) }
    }
}
