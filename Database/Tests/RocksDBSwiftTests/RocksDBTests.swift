// swiftlint:disable force_try
// swiftformat:disable hoistTry
import Foundation
@testable import RocksDBSwift
import Testing

extension String {
    var data: Data {
        Data(utf8)
    }
}

enum Columns: UInt8, Sendable, ColumnFamilyKey {
    case col1
    case col2
    case col3
}

final class RocksDBTests {
    let path = {
        let tmpDir = FileManager.default.temporaryDirectory
        return tmpDir.appendingPathComponent("\(UUID().uuidString)")
    }()

    var rocksDB: RocksDB<Columns>!

    init() throws {
        rocksDB = try RocksDB(path: path)
    }

    deinit {
        rocksDB = nil
        try! FileManager.default.removeItem(at: path)
    }

    @Test func basicOperations() throws {
        #expect(try rocksDB.get(column: .col1, key: "123".data) == nil)

        try rocksDB.put(column: .col1, key: "123".data, value: "qwe".data)
        try rocksDB.put(column: .col1, key: "234".data, value: "asd".data)

        #expect(try rocksDB.get(column: .col1, key: "123".data) == "qwe".data)
        #expect(try rocksDB.get(column: .col1, key: "234".data) == "asd".data)

        try rocksDB.delete(column: .col1, key: "123".data)

        #expect(try rocksDB.get(column: .col1, key: "123".data) == nil)

        try rocksDB.put(column: .col1, key: "234".data, value: "asdfg".data)

        #expect(try rocksDB.get(column: .col1, key: "234".data) == "asdfg".data)
    }

    @Test func batchOperations() throws {
        try rocksDB.put(column: .col1, key: "123".data, value: "qwe".data)

        try rocksDB.batch(operations: [
            .delete(column: Columns.col1.rawValue, key: "123".data),
            .put(column: Columns.col1.rawValue, key: "234".data, value: "wer".data),
            .put(column: Columns.col1.rawValue, key: "345".data, value: "ert".data),
            .delete(column: Columns.col1.rawValue, key: "234".data),
            .put(column: Columns.col1.rawValue, key: "345".data, value: "ertert".data),
        ])

        #expect(try rocksDB.get(column: .col1, key: "123".data) == nil)
        #expect(try rocksDB.get(column: .col1, key: "234".data) == nil)
        #expect(try rocksDB.get(column: .col1, key: "345".data) == "ertert".data)
    }

    @Test func multipleColumnFamilies() throws {
        // Test operations across different column families
        try rocksDB.put(column: .col1, key: "key1".data, value: "value1".data)
        try rocksDB.put(column: .col2, key: "key1".data, value: "value2".data)
        try rocksDB.put(column: .col3, key: "key1".data, value: "value3".data)

        #expect(try rocksDB.get(column: .col1, key: "key1".data) == "value1".data)
        #expect(try rocksDB.get(column: .col2, key: "key1".data) == "value2".data)
        #expect(try rocksDB.get(column: .col3, key: "key1".data) == "value3".data)
    }

    @Test func largeValues() throws {
        // Test handling of large values
        let largeValue = Data((0 ..< 1_000_000).map { UInt8($0 % 256) })
        try rocksDB.put(column: .col1, key: "large".data, value: largeValue)

        let retrieved = try rocksDB.get(column: .col1, key: "large".data)
        #expect(retrieved == largeValue)
    }

    @Test func batchOperationsAcrossColumns() throws {
        // Test batch operations across different column families
        try rocksDB.batch(operations: [
            .put(column: Columns.col1.rawValue, key: "batch1".data, value: "value1".data),
            .put(column: Columns.col2.rawValue, key: "batch2".data, value: "value2".data),
            .put(column: Columns.col3.rawValue, key: "batch3".data, value: "value3".data),
        ])

        #expect(try rocksDB.get(column: .col1, key: "batch1".data) == "value1".data)
        #expect(try rocksDB.get(column: .col2, key: "batch2".data) == "value2".data)
        #expect(try rocksDB.get(column: .col3, key: "batch3".data) == "value3".data)
    }

    @Test func emptyValues() throws {
        // Test handling of empty values
        try rocksDB.put(column: .col1, key: "empty".data, value: Data())

        let retrieved = try rocksDB.get(column: .col1, key: "empty".data)
        #expect(retrieved?.isEmpty == true)
    }

    @Test func testIterator() throws {
        // Setup test data
        let testData = [
            ("key1", "value1"),
            ("key2", "value2"),
            ("key3", "value3"),
            ("key4", "value4"),
            ("key5", "value5"),
        ]

        // Insert test data
        for (key, value) in testData {
            try rocksDB.put(column: .col1, key: key.data, value: value.data)
        }

        // Test forward iteration
        let readOptions = ReadOptions()
        let iterator = rocksDB.createIterator(column: .col1, readOptions: readOptions)

        iterator.seek(to: "key1".data)
        var count = 0
        while let pair = iterator.read() {
            let key = try #require(String(data: pair.key, encoding: .utf8))
            let value = try #require(String(data: pair.value, encoding: .utf8))
            #expect(key == testData[count].0)
            #expect(value == testData[count].1)
            count += 1
            iterator.next()
        }
        #expect(count == testData.count)
    }

    @Test func testSnapshot() throws {
        // Insert initial data
        try rocksDB.put(column: .col1, key: "key1".data, value: "value1".data)

        // Create snapshot
        let snapshot = rocksDB.createSnapshot()
        let readOptions = ReadOptions()
        readOptions.setSnapshot(snapshot)

        // Modify data after snapshot
        try rocksDB.put(column: .col1, key: "key1".data, value: "modified".data)
        try rocksDB.put(column: .col1, key: "key2".data, value: "value2".data)

        // Read using snapshot should see original value
        let iterator = rocksDB.createIterator(column: .col1, readOptions: readOptions)
        iterator.seek(to: "key1".data)
        if let pair = iterator.read() {
            let value = try #require(String(data: pair.value, encoding: .utf8))
            #expect(value == "value1")
        }

        // Regular read should see modified value
        let currentValue = try rocksDB.get(column: .col1, key: "key1".data)
        #expect(String(data: try #require(currentValue), encoding: .utf8) == "modified")
    }
}
