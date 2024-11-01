// swiftlint:disable force_try
// swiftformat:disable hoistTry
import Foundation
import Testing

@testable import Database

extension String {
    var data: Data {
        Data(utf8)
    }
}

final class RocksDBTests {
    let path = {
        let tmpDir = FileManager.default.temporaryDirectory
        return tmpDir.appendingPathComponent("\(UUID().uuidString)")
    }()

    var rocksDB: RocksDB!

    init() throws {
        rocksDB = try RocksDB(path: path)
    }

    deinit {
        rocksDB = nil // close it first
        // then delete the files
        try! FileManager.default.removeItem(at: path)
    }

    @Test func basicOperations() throws {
        #expect(try rocksDB.get(key: "123".data) == nil)

        try rocksDB.put(key: "123".data, value: "qwe".data)
        try rocksDB.put(key: "234".data, value: "asd".data)

        #expect(try rocksDB.get(key: "123".data) == "qwe".data)
        #expect(try rocksDB.get(key: "234".data) == "asd".data)

        try rocksDB.delete(key: "123".data)

        #expect(try rocksDB.get(key: "123".data) == nil)

        try rocksDB.put(key: "234".data, value: "asdfg".data)

        #expect(try rocksDB.get(key: "234".data) == "asdfg".data)
    }

    @Test func testBatchOperations() throws {
        try rocksDB.put(key: "123".data, value: "qwe".data)

        try rocksDB.batch(operations: [
            .delete(key: "123".data),
            .put(key: "234".data, value: "wer".data),
            .put(key: "345".data, value: "ert".data),
            .delete(key: "234".data),
            .put(key: "345".data, value: "ertert".data),
        ])

        #expect(try rocksDB.get(key: "123".data) == nil)
        #expect(try rocksDB.get(key: "234".data) == nil)
        #expect(try rocksDB.get(key: "345".data) == "ertert".data)
    }
}
