import Foundation

public protocol StoreCoder<Key, Value>: Sendable {
    associatedtype Key
    associatedtype Value

    func encode(key: Key) throws -> Data
    func encode(value: Value) throws -> Data
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

    public func put(key: Coder.Key, value: Coder.Value) throws {
        let encodedKey = try coder.encode(key: key)
        let encodedValue = try coder.encode(value: value)

        try db.put(column: column, key: encodedKey, value: encodedValue)
    }

    public func delete(key: Coder.Key) throws {
        let encodedKey = try coder.encode(key: key)
        try db.delete(column: column, key: encodedKey)
    }

    public func exists(key: Coder.Key) throws -> Bool {
        let encodedKey = try coder.encode(key: key)
        // it seems like there is no way to check if a key exists so we just try to get it
        return try db.get(column: column, key: encodedKey) != nil
    }

    public func putOperation(key: Coder.Key, value: Coder.Value) throws -> BatchOperation {
        let encodedKey = try coder.encode(key: key)
        let encodedValue = try coder.encode(value: value)
        return .put(column: column.rawValue, key: encodedKey, value: encodedValue)
    }

    public func deleteOperation(key: Coder.Key) throws -> BatchOperation {
        let encodedKey = try coder.encode(key: key)
        return .delete(column: column.rawValue, key: encodedKey)
    }
}
