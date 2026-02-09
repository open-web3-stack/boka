import Foundation
@testable import RocksDBSwift
import Testing

/// First, let's create a simple coder for testing
struct JSONCoder<K: Codable & Encodable, V: Codable>: StoreCoder {
    typealias Key = K
    typealias Value = V

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func encode(key: K) throws -> Data {
        try encoder.encode(key)
    }

    func encode(value: V) throws -> Data {
        try encoder.encode(value)
    }

    func decode(data: Data) throws -> V {
        try decoder.decode(V.self, from: data)
    }
}

/// Test model structures
struct TestKey: Codable, Hashable {
    let id: String
}

struct TestValue: Codable, Equatable {
    let name: String
    let age: Int
    let data: [String]
}

final class StoreTests {
    let path = {
        let tmpDir = FileManager.default.temporaryDirectory
        return tmpDir.appendingPathComponent("\(UUID().uuidString)")
    }()

    var rocksDB: RocksDB<Columns>!
    var store: Store<Columns, JSONCoder<TestKey, TestValue>>!

    init() throws {
        rocksDB = try RocksDB(path: path)
        store = Store(
            db: rocksDB,
            column: .col1,
            coder: JSONCoder(),
        )
    }

    deinit {
        rocksDB = nil
        try! FileManager.default.removeItem(at: path)
    }

    @Test
    func basicOperations() throws {
        let key = TestKey(id: "test1")
        let value = TestValue(name: "John", age: 30, data: ["a", "b", "c"])

        // Test put and get
        try store.put(key: key, value: value)
        let retrieved = try store.get(key: key)
        #expect(retrieved == value)

        // Test exists
        #expect(try store.exists(key: key) == true)

        // Test delete
        try store.delete(key: key)
        #expect(try store.get(key: key) == nil)
        #expect(try store.exists(key: key) == false)
    }

    @Test
    func batchOperations() throws {
        let key1 = TestKey(id: "batch1")
        let key2 = TestKey(id: "batch2")
        let value1 = TestValue(name: "Alice", age: 25, data: ["x"])
        let value2 = TestValue(name: "Bob", age: 35, data: ["y"])

        // Create batch operations
        let putOp1 = try store.putOperation(key: key1, value: value1)
        let putOp2 = try store.putOperation(key: key2, value: value2)

        // Execute batch
        try rocksDB.batch(operations: [putOp1, putOp2])

        // Verify results
        #expect(try store.get(key: key1) == value1)
        #expect(try store.get(key: key2) == value2)

        // Test batch delete
        let deleteOp = try store.deleteOperation(key: key1)
        try rocksDB.batch(operations: [deleteOp])
        #expect(try store.get(key: key1) == nil)
        #expect(try store.get(key: key2) == value2)
    }

    @Test
    func errorHandling() throws {
        // Test getting non-existent key
        let nonExistentKey = TestKey(id: "nothere")
        #expect(try store.get(key: nonExistentKey) == nil)

        // Test multiple operations
        let key = TestKey(id: "test")
        let value1 = TestValue(name: "First", age: 20, data: ["1"])
        let value2 = TestValue(name: "Second", age: 30, data: ["2"])

        try store.put(key: key, value: value1)
        try store.put(key: key, value: value2)

        let final = try store.get(key: key)
        #expect(final == value2)
    }

    @Test
    func largeData() throws {
        let key = TestKey(id: "large")
        let largeArray = (0 ..< 1000).map { String($0) }
        let value = TestValue(name: "Large", age: 99, data: largeArray)

        try store.put(key: key, value: value)
        let retrieved = try store.get(key: key)
        #expect(retrieved == value)
    }

    @Test
    func multipleStores() throws {
        // Create a second store with different types
        let store2: Store<Columns, JSONCoder<String, Int>> = Store(
            db: rocksDB,
            column: .col2,
            coder: JSONCoder(),
        )

        // Test operations on both stores
        let key1 = TestKey(id: "store1")
        let value1 = TestValue(name: "Store1", age: 40, data: ["test"])

        try store.put(key: key1, value: value1)
        try store2.put(key: "store2", value: 42)

        #expect(try store.get(key: key1) == value1)
        #expect(try store2.get(key: "store2") == 42)
    }
}
