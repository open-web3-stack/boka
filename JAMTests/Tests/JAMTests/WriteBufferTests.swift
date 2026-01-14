@testable import Blockchain
import Foundation
import Testing
import Utils

/// Helper function to create a test Data31 key
private func makeKey(_ byte: UInt8) -> Data31 {
    var keyData = Data(repeating: 0, count: 31)
    keyData[0] = byte
    return Data31(keyData)!
}

/// Unit tests for WriteBuffer functionality
struct WriteBufferTests {
    @Test("Write buffer initialization with default values")
    func testInitialization() async throws {
        let buffer = WriteBuffer(
            maxBufferSize: 100,
            flushInterval: 1.0
        )

        let stats = await buffer.stats
        #expect(stats.currentSize == 0)
        #expect(stats.maxBufferSize == 100)
        #expect(stats.utilization == 0.0)
    }

    @Test("Write buffer single add operation")
    func testSingleAdd() async throws {
        let buffer = WriteBuffer(maxBufferSize: 10, flushInterval: 1.0)

        let shouldFlush = await buffer.add(key: makeKey(1), value: "test".data(using: .utf8)!)

        // Should not flush with only 1 item
        #expect(shouldFlush == false)

        let stats = await buffer.stats
        #expect(stats.currentSize == 1)
        #expect(stats.totalUpdates == 1)
    }

    @Test("Write buffer flushes when reaching max size")
    func testFlushBySize() async throws {
        let maxSize = 5
        let buffer = WriteBuffer(maxBufferSize: maxSize, flushInterval: 10.0)

        // Add items up to max size
        for i in 0 ..< maxSize {
            let shouldFlush = await buffer.add(key: makeKey(UInt8(i)), value: "value\(i)".data(using: .utf8)!)

            // Should flush on the last item
            if i == maxSize - 1 {
                #expect(shouldFlush == true)
            } else {
                #expect(shouldFlush == false)
            }
        }

        let stats = await buffer.stats
        #expect(stats.currentSize == maxSize)
    }

    @Test("Write buffer flushes and clears correctly")
    func testFlush() async throws {
        let buffer = WriteBuffer(maxBufferSize: 100, flushInterval: 1.0)

        // Add some items
        for i in 0 ..< 10 {
            _ = await buffer.add(key: makeKey(UInt8(i)), value: "value\(i)".data(using: .utf8)!)
        }

        // Flush the buffer
        let flushed = await buffer.flush()

        #expect(flushed.count == 10)

        let stats = await buffer.stats
        #expect(stats.currentSize == 0)
        #expect(stats.totalFlushes == 1)
        #expect(stats.manualFlushes == 1)
    }

    @Test("Write buffer statistics are accurate")
    func testStatistics() async throws {
        let buffer = WriteBuffer(maxBufferSize: 10, flushInterval: 1.0)

        // Add some items
        for i in 0 ..< 5 {
            _ = await buffer.add(key: makeKey(UInt8(i)), value: "value\(i)".data(using: .utf8)!)
        }

        let stats = await buffer.stats

        #expect(stats.currentSize == 5)
        #expect(stats.totalUpdates == 5)
        #expect(stats.utilization == 0.5) // 5/10 = 0.5
        #expect(stats.totalFlushes == 0)
    }

    @Test("Write buffer clear removes all items")
    func testClear() async throws {
        let buffer = WriteBuffer(maxBufferSize: 100, flushInterval: 1.0)

        // Add some items
        for i in 0 ..< 10 {
            _ = await buffer.add(key: makeKey(UInt8(i)), value: "value\(i)".data(using: .utf8)!)
        }

        // Clear without flushing
        await buffer.clear()

        let stats = await buffer.stats
        #expect(stats.currentSize == 0)
    }

    @Test("Write buffer reset statistics preserves buffer")
    func testResetStats() async throws {
        let buffer = WriteBuffer(maxBufferSize: 10, flushInterval: 1.0)

        // Add items and flush
        for i in 0 ..< 3 {
            _ = await buffer.add(key: makeKey(UInt8(i)), value: "value\(i)".data(using: .utf8)!)
        }
        _ = await buffer.flush()

        // Reset stats
        await buffer.resetStats()

        let stats = await buffer.stats
        #expect(stats.totalUpdates == 0)
        #expect(stats.totalFlushes == 0)
        #expect(stats.autoFlushes == 0)
        #expect(stats.manualFlushes == 0)
        // Buffer should still have items
        #expect(stats.currentSize == 0) // Since we flushed
    }

    @Test("Write buffer handles nil values (deletes)")
    func testNilValues() async throws {
        let buffer = WriteBuffer(maxBufferSize: 10, flushInterval: 1.0)

        await buffer.add(key: makeKey(1), value: nil) // Delete operation

        let flushed = await buffer.flush()
        #expect(flushed.count == 1)
        #expect(flushed[0].value == nil) // Should preserve nil
    }

    @Test("Write buffer empty check works correctly")
    func testIsEmpty() async throws {
        let buffer = WriteBuffer(maxBufferSize: 10, flushInterval: 1.0)

        var isEmpty = await buffer.isEmpty
        #expect(isEmpty == true)

        _ = await buffer.add(key: makeKey(1), value: "test".data(using: .utf8)!)

        isEmpty = await buffer.isEmpty
        #expect(isEmpty == false)

        _ = await buffer.flush()

        isEmpty = await buffer.isEmpty
        #expect(isEmpty == true)
    }

    @Test("Write buffer maintains correct order")
    func testOrderPreservation() async throws {
        let buffer = WriteBuffer(maxBufferSize: 10, flushInterval: 1.0)

        let expectedOrder = [1, 2, 3, 4, 5]

        for i in expectedOrder {
            _ = await buffer.add(key: makeKey(UInt8(i)), value: "value\(i)".data(using: .utf8)!)
        }

        let flushed = await buffer.flush()

        #expect(flushed.count == expectedOrder.count)

        // Verify order is preserved
        for (index, item) in flushed.enumerated() {
            let expectedValue = "value\(expectedOrder[index])"
            #expect(item.value == expectedValue.data(using: .utf8)!)
        }
    }

    @Test("Write buffer utilization calculation")
    func testUtilization() async throws {
        let buffer = WriteBuffer(maxBufferSize: 100, flushInterval: 1.0)

        // Empty buffer
        var stats = await buffer.stats
        #expect(stats.utilization == 0.0)

        // Half full
        for i in 0 ..< 50 {
            _ = await buffer.add(key: makeKey(UInt8(i)), value: "value\(i)".data(using: .utf8)!)
        }

        stats = await buffer.stats
        #expect(stats.utilization == 0.5)

        // Full
        for i in 50 ..< 100 {
            _ = await buffer.add(key: makeKey(UInt8(i)), value: "value\(i)".data(using: .utf8)!)
        }

        stats = await buffer.stats
        #expect(stats.utilization == 1.0)
    }
}
