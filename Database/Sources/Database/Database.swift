// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation
import RocksDB

public class Database {
    public let path: URL
    public let prefix: String?
    private var db: RocksDB?

    private static let errorDomain = "DatabaseErrorDomain"

    public init(path: URL, prefix: String? = nil) throws {
        self.path = path
        self.prefix = prefix

        do {
            db = try RocksDB(path: path, prefix: prefix)
        } catch {
            throw NSError(domain: Database.errorDomain, code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize RocksDB: \(error)"])
        }
    }

    public func put(key: String, value: some RocksDBValueRepresentable) throws {
        guard let db else {
            throw NSError(domain: Database.errorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: "Database is not opened"])
        }
        do {
            try db.put(key: key, value: value)
        } catch {
            throw error
        }
    }

    public func get<T: RocksDBValueInitializable>(type: T.Type, key: String) throws -> T? {
        guard let db else {
            throw NSError(domain: Database.errorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: "Database is not opened"])
        }
        do {
            return try type.init(data: db.get(key: key))
        } catch {
            throw error
        }
    }

    public func delete(key: String) throws {
        guard let db else {
            throw NSError(domain: Database.errorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: "Database is not opened"])
        }
        do {
            try db.delete(key: key)
        } catch {
            throw error
        }
    }

    public func iterate<Key: RocksDBValueInitializable, Value: RocksDBValueInitializable>(
        keyType _: Key.Type,
        valueType _: Value.Type,
        gte: String? = nil
    ) throws -> RocksDBSequence<Key, Value> {
        guard let db else {
            throw NSError(domain: Database.errorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: "Database is not opened"])
        }

        return db.sequence(gte: gte)
    }

    public func iterate<Key: RocksDBValueInitializable, Value: RocksDBValueInitializable>(keyType _: Key.Type, valueType _: Value.Type,
                                                                                          lte: String) throws -> RocksDBSequence<Key, Value>
    {
        guard let db else {
            throw NSError(domain: Database.errorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: "Database is not opened"])
        }

        return db.sequence(lte: lte)
    }

    public func batch(operations: [RocksDBBatchOperation<String>]) throws {
        guard let db else {
            throw NSError(domain: Database.errorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: "Database is not opened"])
        }

        do {
            try db.batch(operations: operations)
        } catch {
            throw error
        }
    }
}
