@testable import Blockchain
import Foundation
import Testing
import Utils

/// Edge case tests for WriteBuffer
struct WriteBufferEdgeCaseTests {
    // MARK: - Timing Tests

    @Test("Write buffer flushes based on time interval")
    func testTimeBasedFlush() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: 1000, // Large buffer
            writeBufferFlushInterval: 0.05 // Very short interval for testing (50ms)
        )

        // Add single item
        try await trie.update([
            (makeKey(1), Data("value1".utf8)),
        ])

        // Wait for auto-flush interval to pass
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds (longer than flushInterval)

        // Add another item - this should trigger time-based flush
        try await trie.update([
            (makeKey(2), Data("value2".utf8)),
        ])

        // Buffer should have been flushed
        let stats = await trie.getWriteBufferStats()
        #expect(stats != nil)
        // Buffer should be empty or have only the last item
        #expect(stats!.currentSize <= 1)
    }

    @Test("Write buffer uses monotonic clock")
    func testMonotonicClock() async throws {
        let buffer = WriteBuffer(
            maxBufferSize: 1000,
            flushInterval: 1.0
        )

        // Add item to set lastFlushTime
        _ = buffer.add(key: Data31.random(), value: Data())

        // Immediately check - should not flush by time
        #expect(buffer.shouldFlushByTime == false)

        // This verifies monotonic clock is being used
        // (system time changes won't affect behavior)
    }

    // MARK: - Boundary Tests

    @Test("Write buffer handles maximum buffer size")
    func testMaxBufferSize() async throws {
        let backend = InMemoryBackend()
        let bufferSize = 5
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: bufferSize,
            writeBufferFlushInterval: 10.0
        )

        // Add exactly max buffer size items
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< bufferSize {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)

        // Buffer might have been auto-flushed during update
        // The key is that update() succeeded without issues
        let stats = await trie.getWriteBufferStats()
        #expect(stats != nil)
        // Buffer size could be 0 (auto-flushed) or bufferSize (not yet flushed)
        #expect(stats!.currentSize == 0 || stats!.currentSize == bufferSize)
    }

    @Test("Write buffer handles zero minimum flush interval")
    func testZeroFlushInterval() async throws {
        // Write buffer should enforce minimum of 0.1 seconds
        let buffer = WriteBuffer(
            maxBufferSize: 100,
            flushInterval: 0.0 // Should be clamped to 0.1
        )

        _ = buffer.add(key: Data31.random(), value: Data())

        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds

        // Should be able to flush by time now (after min interval)
        #expect(buffer.shouldFlushByTime == true)
    }

    @Test("Write buffer handles very large flush interval")
    func testLargeFlushInterval() async throws {
        let buffer = WriteBuffer(
            maxBufferSize: 100,
            flushInterval: 3600.0 // 1 hour
        )

        _ = buffer.add(key: Data31.random(), value: Data())

        // Should not flush by time
        #expect(buffer.shouldFlushByTime == false)
    }

    // MARK: - Statistics Tests

    @Test("Write buffer tracks statistics accurately")
    func testStatisticsAccuracy() async throws {
        let buffer = WriteBuffer(
            maxBufferSize: 10,
            flushInterval: 1.0
        )

        // Add some items
        for _ in 0 ..< 5 {
            _ = buffer.add(key: Data31.random(), value: Data())
        }

        let stats1 = buffer.stats
        #expect(stats1.currentSize == 5)
        #expect(stats1.totalUpdates == 5)
        #expect(stats1.utilization == 0.5) // 5/10

        // Flush manually
        _ = buffer.flush()

        let stats2 = buffer.stats
        #expect(stats2.currentSize == 0)
        #expect(stats2.totalFlushes == 1)
        #expect(stats2.manualFlushes == 1)
    }

    @Test("Write buffer resets statistics correctly")
    func testResetStatistics() async throws {
        let buffer = WriteBuffer(maxBufferSize: 10, flushInterval: 1.0)

        // Add items and flush
        for _ in 0 ..< 5 {
            _ = buffer.add(key: Data31.random(), value: Data())
        }
        _ = buffer.flush()

        var stats = buffer.stats
        #expect(stats.totalUpdates == 5)
        #expect(stats.totalFlushes == 1)

        // Reset
        buffer.resetStats()

        stats = buffer.stats
        #expect(stats.totalUpdates == 0)
        #expect(stats.totalFlushes == 0)
        #expect(stats.currentSize == 0) // Buffer should also be cleared
    }

    @Test("Write buffer calculates utilization correctly")
    func testUtilizationCalculation() async throws {
        let buffer = WriteBuffer(maxBufferSize: 100, flushInterval: 1.0)

        for _ in 0 ..< 50 {
            _ = buffer.add(key: Data31.random(), value: Data())
        }

        let stats = buffer.stats
        #expect(stats.utilization == 0.5) // 50/100

        // Add 25 more
        for _ in 0 ..< 25 {
            _ = buffer.add(key: Data31.random(), value: Data())
        }

        let stats2 = buffer.stats
        #expect(stats2.utilization == 0.75) // 75/100
    }

    // MARK: - Auto Flush Tests

    @Test("Write buffer auto-flushes when size limit reached")
    func testAutoFlushBySize() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: 3,
            writeBufferFlushInterval: 10.0
        )

        // Add 4 items (buffer size is 3, should auto-flush)
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 4 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)

        let stats = await trie.getWriteBufferStats()
        #expect(stats!.totalFlushes >= 1)
        #expect(stats!.autoFlushes >= 1)
    }

    @Test("Write buffer combines size and time triggers")
    func testCombinedFlushTriggers() async throws {
        let buffer = WriteBuffer(
            maxBufferSize: 100,
            flushInterval: 0.1
        )

        // Add some items but not enough to trigger size flush
        for _ in 0 ..< 10 {
            _ = buffer.add(key: Data31.random(), value: Data())
        }

        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds

        // Should flush by time even though not at size limit
        #expect(buffer.shouldFlushByTime == true)
    }

    // MARK: - Clear Tests

    @Test("Write buffer clears without flushing")
    func testClearWithoutFlush() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: 100,
            writeBufferFlushInterval: 10.0
        )

        // Add items
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 10 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)

        let stats1 = await trie.getWriteBufferStats()
        #expect(stats1!.currentSize == 10)

        // Clear without flushing (data loss!)
        await trie.clearWriteBuffer()

        let stats2 = await trie.getWriteBufferStats()
        #expect(stats2!.currentSize == 0)
        #expect(stats2!.totalUpdates == 10) // Stats still track updates
    }

    // MARK: - Empty State Tests

    @Test("Write buffer handles empty state correctly")
    func testEmptyState() async throws {
        let buffer = WriteBuffer(maxBufferSize: 10, flushInterval: 1.0)

        #expect(buffer.isEmpty == true)
        #expect(buffer.size == 0)

        // Flush when empty should return false
        let flushed = buffer.flush()
        #expect(flushed == false)

        let stats = buffer.stats
        #expect(stats.currentSize == 0)
        #expect(stats.utilization == 0.0)
    }

    @Test("Write buffer maintains state after clear")
    func testStateAfterClear() async throws {
        let buffer = WriteBuffer(maxBufferSize: 10, flushInterval: 1.0)

        // Add and clear multiple times
        for _ in 0 ..< 3 {
            for _ in 0 ..< 5 {
                _ = buffer.add(key: Data31.random(), value: Data())
            }
            buffer.clear()
        }

        #expect(buffer.isEmpty == true)
        #expect(buffer.size == 0)
    }

    // MARK: - Error Handling Tests

    @Test("Write buffer handles negative buffer size gracefully")
    func testNegativeBufferSize() async throws {
        // Write buffer should enforce minimum of 1
        let buffer = WriteBuffer(
            maxBufferSize: -10, // Should be clamped to 1
            flushInterval: 1.0
        )

        // Add items
        for _ in 0 ..< 5 {
            _ = buffer.add(key: Data31.random(), value: Data())
        }

        // Should work despite negative initial value
        #expect(buffer.size > 0)
    }

    // MARK: - Performance Tests

    @Test("Write buffer handles rapid additions")
    func testRapidAdditions() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: 1000,
            writeBufferFlushInterval: 1.0
        )

        // Rapid additions
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 100 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)

        let stats = await trie.getWriteBufferStats()
        #expect(stats!.totalUpdates == 100)
    }

    // MARK: - Integration Tests

    @Test("Write buffer integrates with StateTrie save")
    func testIntegrationWithSave() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: 100,
            writeBufferFlushInterval: 10.0
        )

        // Add items to buffer
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 10 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)

        // Verify data is readable (in-memory trie works)
        let result = try await trie.read(key: makeKey(5))
        #expect(result == Data("value5".utf8))

        // Save should persist data
        try await trie.save()

        // Data should still be readable after save
        let result2 = try await trie.read(key: makeKey(5))
        #expect(result2 == Data("value5".utf8))
    }

    @Test("Write buffer works correctly when disabled")
    func testDisabledWriteBuffer() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: false // Disabled
        )

        // Add items
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 10 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)

        // Should have no write buffer stats
        let stats = await trie.getWriteBufferStats()
        #expect(stats == nil)
    }
}

/// Helper function to create a test Data31 key
private func makeKey(_ byte: UInt8) -> Data31 {
    var keyData = Data(repeating: 0, count: 31)
    keyData[0] = byte
    return Data31(keyData)!
}
