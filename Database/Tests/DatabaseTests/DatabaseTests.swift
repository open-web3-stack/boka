@testable import Database
import XCTest

final class DatabaseTests: XCTestCase {
    var database: Database!

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testSimplePut() {
        let path = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)")
        database = Database(path: path)

        do {
            try database.put(key: "testText", value: "lolamkhaha")
            try database.put(key: "testEmoji", value: "😂")
            try database.put(key: "testTextEmoji", value: "emojitext 😂")
            try database.put(key: "testMultipleEmoji", value: "😂😂😂")

            XCTAssertEqual(try database.get(type: String.self, key: "testText"), "lolamkhaha")
            XCTAssertEqual(try database.get(type: String.self, key: "testEmoji"), "😂")
            XCTAssertEqual(try database.get(type: String.self, key: "testTextEmoji"), "emojitext 😂")
            XCTAssertEqual(try database.get(type: String.self, key: "testMultipleEmoji"), "😂😂😂")
        } catch {
            XCTFail("An error occurred during simple put test: \(error)")
        }

        do {
            try FileManager.default.removeItem(at: database.path)
            database = nil
        } catch {
            XCTFail("Failed to remove RocksDB path: \(error)")
        }
    }

    func testSimpleDelete() {
        let path = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)")
        database = Database(path: path)

        do {
            try database.put(key: "testDeleteKey", value: "this is a simple value 😘")
            try database.delete(key: "testDeleteKey")

            XCTAssertEqual(try database.get(type: String.self, key: "testDeleteKey"), "")

        } catch {
            XCTFail("An error occurred during simple delete test: \(error)")
        }
        do {
            try FileManager.default.removeItem(at: database.path)
            database = nil
        } catch {
            XCTFail("Failed to remove RocksDB path: \(error)")
        }
    }

    func testSimpleIterator() {
        let path = "/tmp/\(UUID().uuidString)"
        database = Database(path: URL(fileURLWithPath: path))

        let orderedKeysAndValues = [
            (key: "testEmoji", value: "😂"),
            (key: "testMultipleEmoji", value: "😂😂😂"),
            (key: "testText", value: "lolamkhaha"),
            (key: "testTextEmoji", value: "emojitext 😂"),
        ]

        do {
            for (k, v) in orderedKeysAndValues {
                try database.put(key: k, value: v)
            }
        } catch {
            XCTFail("An error occurred during simple iterator test: \(error)")
        }

        var i = 0
        for (key, val) in try! database.iterate(keyType: String.self, valueType: String.self) {
            XCTAssertEqual(key, orderedKeysAndValues[i].key)
            XCTAssertEqual(val, orderedKeysAndValues[i].value)
            i += 1
        }
        XCTAssertEqual(i, 4)

        i = 1
        for (key, val) in try! database.iterate(keyType: String.self, valueType: String.self, gte: "testMultipleEmoji") {
            XCTAssertEqual(key, orderedKeysAndValues[i].key)
            XCTAssertEqual(val, orderedKeysAndValues[i].value)
            i += 1
        }
        XCTAssertEqual(i, 4)

        i = 2
        for (key, val) in try! database.iterate(keyType: String.self, valueType: String.self, gte: "testText") {
            XCTAssertEqual(key, orderedKeysAndValues[i].key)
            XCTAssertEqual(val, orderedKeysAndValues[i].value)
            i += 1
        }
        XCTAssertEqual(i, 4)

        i = 3
        for (key, val) in try! database.iterate(keyType: String.self, valueType: String.self, lte: "testTextEmoji") {
            XCTAssertEqual(key, orderedKeysAndValues[i].key)
            XCTAssertEqual(val, orderedKeysAndValues[i].value)
            i -= 1
        }
        XCTAssertEqual(i, -1)

        i = 2
        for (key, val) in try! database.iterate(keyType: String.self, valueType: String.self, lte: "testText") {
            XCTAssertEqual(key, orderedKeysAndValues[i].key)
            XCTAssertEqual(val, orderedKeysAndValues[i].value)
            i -= 1
        }
        XCTAssertEqual(i, -1)

        do {
            try FileManager.default.removeItem(at: database.path)
            database = nil
        } catch {
            XCTFail("Failed to remove RocksDB path: \(error)")
        }
    }

    func testBatchOperations() {
        let prefixedPath = "/tmp/\(UUID().uuidString)"

        let prefixedDB = Database(path: URL(fileURLWithPath: prefixedPath), prefix: "correctprefix")

        do {
            try prefixedDB.put(key: "testText", value: "lolamkhaha")
            try prefixedDB.put(key: "testEmoji", value: "😂")
            try prefixedDB.put(key: "testTextEmoji", value: "emojitext 😂")
            try prefixedDB.put(key: "testMultipleEmoji", value: "😂😂😂")

            try prefixedDB.batch(operations: [
                .delete(key: "testText"),
                .put(key: "someThing", value: "someValue"),
                .delete(key: "someThing"),
                .put(key: "secondKey", value: "anotherValue"),
                .put(key: "testText", value: "textTextValue"),
            ])

            XCTAssertEqual(try prefixedDB.get(type: String.self, key: "testEmoji"), "😂")
            XCTAssertEqual(try prefixedDB.get(type: String.self, key: "someThing"), "")
            XCTAssertEqual(try prefixedDB.get(type: String.self, key: "secondKey"), "anotherValue")
            XCTAssertEqual(try prefixedDB.get(type: String.self, key: "testText"), "textTextValue")

        } catch {
            XCTFail("An error occurred during batch test: \(error)")
        }
        try! FileManager.default.removeItem(at: prefixedDB.path)
    }
}
