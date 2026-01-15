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

/// Integration tests for StateTrie with write buffering
struct StateTrieWriteBufferIntegrationTests {
    @Test("State trie with write buffering enabled")
    func testStateTrieWithWriteBuffer() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: 10,
            writeBufferFlushInterval: 1.0
        )

        // Perform updates
        let updates = [
            (makeKey(1), Data("value1".utf8)),
            (makeKey(2), Data("value2".utf8)),
            (makeKey(3), Data("value3".utf8)),
        ]

        try await trie.update(updates)

        // Flush to ensure persistence
        try await trie.flush()

        // Verify we can read back
        let result1 = try await trie.read(key: makeKey(1))
        #expect(result1 == Data("value1".utf8))
    }

    @Test("State trie auto-flushes when buffer is full")
    func testAutoFlushBySize() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: 5,
            writeBufferFlushInterval: 10.0
        )

        // Add 6 items (buffer size is 5, so should auto-flush)
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 6 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)

        // Check buffer stats
        let stats = await trie.getWriteBufferStats()
        #expect(stats != nil)
        #expect(stats!.totalFlushes >= 1) // Should have auto-flushed
    }

    @Test("State trie flushes before read for consistency")
    func testReadConsistency() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: 100,
            writeBufferFlushInterval: 10.0
        )

        // Add an item without manual flush
        try await trie.update([
            (makeKey(1), Data("test".utf8)),
        ])

        // Read should still return the value (read sees in-memory updates, no flush needed)
        let result = try await trie.read(key: makeKey(1))
        #expect(result == Data("test".utf8))
    }

    @Test("State trie write buffer statistics")
    func testWriteBufferStatistics() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: 50,
            writeBufferFlushInterval: 1.0
        )

        // Perform some updates
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 10 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)

        // Check statistics
        let stats = await trie.getWriteBufferStats()
        #expect(stats != nil)
        #expect(stats!.currentSize == 10)
        #expect(stats!.totalUpdates == 10)
    }

    @Test("State trie manual flush works correctly")
    func testManualFlush() async throws {
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
        for i in 0 ..< 5 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)

        // Manual flush
        try await trie.flush()

        // Buffer should be empty after flush
        let stats = await trie.getWriteBufferStats()
        #expect(stats!.currentSize == 0)
    }

    @Test("State trie with write buffering disabled")
    func testWriteBufferDisabled() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: false // Disabled
        )

        // Perform updates
        let updates = [
            (makeKey(1), Data("value1".utf8)),
        ]

        try await trie.update(updates)

        // Should have no write buffer stats
        let stats = await trie.getWriteBufferStats()
        #expect(stats == nil)
    }

    @Test("State trie handles deletes in write buffer")
    func testWriteBufferWithDeletes() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: 10,
            writeBufferFlushInterval: 1.0
        )

        let key = makeKey(1)

        // Insert
        try await trie.update([
            (key, Data("value1".utf8)),
        ])

        // Delete
        try await trie.update([
            (key, nil),
        ])

        try await trie.flush()

        // Verify deletion
        let result = try await trie.read(key: key)
        #expect(result == nil)
    }

    @Test("State trie clear write buffer")
    func testClearWriteBuffer() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: 100,
            writeBufferFlushInterval: 1.0
        )

        // Add items to buffer
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 10 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)

        // Clear buffer (data loss!)
        await trie.clearWriteBuffer()

        // Buffer should be empty
        let stats = await trie.getWriteBufferStats()
        #expect(stats!.currentSize == 0)
    }

    @Test("State trie maintains consistency with mixed operations")
    func testMixedOperationsConsistency() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: true,
            writeBufferSize: 10,
            writeBufferFlushInterval: 1.0
        )

        let key1 = makeKey(1)
        let key2 = makeKey(2)

        // Insert
        try await trie.update([
            (key1, Data("value1".utf8)),
        ])

        // Read (sees in-memory updates, no flush needed)
        let result1 = try await trie.read(key: key1)
        #expect(result1 == Data("value1".utf8))

        // Insert another
        try await trie.update([
            (key2, Data("value2".utf8)),
        ])

        // Read both (reads see in-memory updates)
        let result2 = try await trie.read(key: key1)
        let result3 = try await trie.read(key: key2)

        #expect(result2 == Data("value1".utf8))
        #expect(result3 == Data("value2".utf8))
    }
}
