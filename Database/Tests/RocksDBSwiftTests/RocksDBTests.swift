// swiftlint:disable force_try
// swiftformat:disable hoistTry
import Foundation
import Testing

@testable import RocksDBSwift

extension String {
    var data: Data { Data(utf8) }
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

    @Test func testBatchOperations() throws {
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

    @Test func testMultipleColumnFamilies() throws {
        // Test operations across different column families
        try rocksDB.put(column: .col1, key: "key1".data, value: "value1".data)
        try rocksDB.put(column: .col2, key: "key1".data, value: "value2".data)
        try rocksDB.put(column: .col3, key: "key1".data, value: "value3".data)

        #expect(try rocksDB.get(column: .col1, key: "key1".data) == "value1".data)
        #expect(try rocksDB.get(column: .col2, key: "key1".data) == "value2".data)
        #expect(try rocksDB.get(column: .col3, key: "key1".data) == "value3".data)
    }

    @Test func testLargeValues() throws {
        // Test handling of large values
        let largeValue = Data((0 ..< 1_000_000).map { UInt8($0 % 256) })
        try rocksDB.put(column: .col1, key: "large".data, value: largeValue)

        let retrieved = try rocksDB.get(column: .col1, key: "large".data)
        #expect(retrieved == largeValue)
    }

    @Test func testBatchOperationsAcrossColumns() throws {
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

    @Test func testEmptyValues() throws {
        // Test handling of empty values
        try rocksDB.put(column: .col1, key: "empty".data, value: Data())

        let retrieved = try rocksDB.get(column: .col1, key: "empty".data)
        #expect(retrieved?.isEmpty == true)
    }

    @Test func testErrorConditions() throws {
        // Test invalid operations
        let invalidDB = try? RocksDB<Columns>(path: URL(fileURLWithPath: "/nonexistent/path"))
        #expect(invalidDB == nil)

        // Test deleting non-existent key
        try rocksDB.delete(column: .col1, key: "nonexistent".data)
        let value = try rocksDB.get(column: .col1, key: "nonexistent".data)
        #expect(value == nil)
    }
}
