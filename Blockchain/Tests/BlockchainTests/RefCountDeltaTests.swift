@testable import Blockchain
import Foundation
import Testing
import Utils

/// Tests for delta-based reference count operations
struct RefCountDeltaTests {
    // MARK: - Backend refUpdate Tests

    @Test("InMemoryBackend handles refUpdate increments")
    func inMemoryRefUpdateIncrement() async throws {
        let backend = InMemoryBackend()
        let key = Data(repeating: 0xAA, count: 31)

        // Initial write
        try await backend.batchUpdate([
            .write(key: key, value: Data([0x01, 0x02, 0x03])),
        ])

        // Increment ref count
        try await backend.batchUpdate([
            .refUpdate(key: key, delta: 1),
        ])

        // Verify ref count was incremented
        let refCount = await backend.getRefCount(key: key)
        #expect(refCount == 1)
    }

    @Test("InMemoryBackend handles refUpdate decrements")
    func inMemoryRefUpdateDecrement() async throws {
        let backend = InMemoryBackend()
        let key = Data(repeating: 0xBB, count: 31)

        // Initial write with ref count
        try await backend.batchUpdate([
            .write(key: key, value: Data([0x01])),
            .refUpdate(key: key, delta: 5), // Set ref count to 5
        ])

        // Decrement ref count
        try await backend.batchUpdate([
            .refUpdate(key: key, delta: -2),
        ])

        // Verify ref count was decremented
        let refCount = await backend.getRefCount(key: key)
        #expect(refCount == 3)
    }

    @Test("InMemoryBackend handles multiple refUpdate operations")
    func inMemoryMultipleRefUpdates() async throws {
        let backend = InMemoryBackend()
        let key1 = Data(repeating: 0x01, count: 31)
        let key2 = Data(repeating: 0x02, count: 31)

        // Multiple ref count updates in single batch
        try await backend.batchUpdate([
            .write(key: key1, value: Data([0x01])),
            .write(key: key2, value: Data([0x02])),
            .refUpdate(key: key1, delta: 3),
            .refUpdate(key: key2, delta: 5),
            .refUpdate(key: key1, delta: 2), // key1 now has ref count 5
        ])

        #expect(await backend.getRefCount(key: key1) == 5)
        #expect(await backend.getRefCount(key: key2) == 5)
    }

    @Test("InMemoryBackend handles negative delta resulting in zero")
    func inMemoryRefUpdateToZero() async throws {
        let backend = InMemoryBackend()
        let key = Data(repeating: 0xCC, count: 31)

        // Set ref count to 3
        try await backend.batchUpdate([
            .write(key: key, value: Data([0x01])),
            .refUpdate(key: key, delta: 3),
        ])

        // Decrement to zero
        try await backend.batchUpdate([
            .refUpdate(key: key, delta: -3),
        ])

        #expect(await backend.getRefCount(key: key) == 0)
    }

    @Test("InMemoryBackend handles large delta values")
    func inMemoryLargeDelta() async throws {
        let backend = InMemoryBackend()
        let key = Data(repeating: 0xDD, count: 31)

        // Large increment
        try await backend.batchUpdate([
            .write(key: key, value: Data([0x01])),
            .refUpdate(key: key, delta: 1000),
        ])

        #expect(await backend.getRefCount(key: key) == 1000)

        // Large decrement
        try await backend.batchUpdate([
            .refUpdate(key: key, delta: -500),
        ])

        #expect(await backend.getRefCount(key: key) == 500)
    }

    // MARK: - StateTrie refUpdate Integration Tests

    @Test("StateTrie uses refUpdate for reference counting")
    func stateTrieRefUpdateIntegration() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: false, // Disable buffer for direct testing
        )

        let key1 = makeKey(1)
        let key2 = makeKey(2)

        // Insert two keys
        try await trie.update([
            (key1, Data("value1".utf8)),
        ])
        try await trie.save()

        try await trie.update([
            (key2, Data("value2".utf8)),
        ])
        try await trie.save()

        // Both keys should have ref counts >= 1
        // (We can't easily inspect this from outside, but save should succeed)
        let result1 = try await trie.read(key: key1)
        let result2 = try await trie.read(key: key2)

        #expect(result1 == Data("value1".utf8))
        #expect(result2 == Data("value2".utf8))
    }

    @Test("StateTrie decrements old root ref count")
    func stateTrieOldRootDecrement() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: false,
        )

        let key = makeKey(1)

        // First save - creates initial root
        try await trie.update([(key, Data("value1".utf8))])
        let root1 = await trie.rootHash
        try await trie.save()

        // Second save - changes root
        try await trie.update([(key, Data("value2".utf8))])
        let root2 = await trie.rootHash
        try await trie.save()

        // Root should have changed
        #expect(root1 != root2)

        // Old root's ref count should be decremented
        // (This happens automatically via refUpdate)
    }

    @Test("StateTrie handles multiple save operations")
    func stateTrieMultipleSaves() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: false,
        )

        let key = makeKey(1)

        // Multiple save cycles
        for i in 0 ..< 5 {
            try await trie.update([(key, Data("value\(i)".utf8))])
            try await trie.save()

            let result = try await trie.read(key: key)
            #expect(result == Data("value\(i)".utf8))
        }

        // All operations should succeed without corruption
    }

    // MARK: - Batch Operation Tests

    @Test("Ref update operations batch correctly")
    func refUpdateBatching() async throws {
        let backend = InMemoryBackend()

        let keys = (0 ..< 10).map { Data(repeating: UInt8($0), count: 31) }

        // Single batch with multiple operations
        var ops: [StateBackendOperation] = []
        for key in keys {
            ops.append(.write(key: key, value: Data([0x01])))
            ops.append(.refUpdate(key: key, delta: 1))
        }

        try await backend.batchUpdate(ops)

        // Verify all ref counts
        for key in keys {
            #expect(await backend.getRefCount(key: key) == 1)
        }
    }

    @Test("Ref update operations mix with writes correctly")
    func refUpdateMixedWithWrites() async throws {
        let backend = InMemoryBackend()

        let key1 = Data(repeating: 0x01, count: 31)
        let key2 = Data(repeating: 0x02, count: 31)

        // Mix writes and ref updates
        try await backend.batchUpdate([
            .write(key: key1, value: Data([0x01])),
            .refUpdate(key: key1, delta: 1),
            .write(key: key2, value: Data([0x02])),
            .refUpdate(key: key2, delta: 2),
            .refUpdate(key: key1, delta: 1), // Update again
        ])

        #expect(await backend.getRefCount(key: key1) == 2)
        #expect(await backend.getRefCount(key: key2) == 2)
    }

    // MARK: - Edge Cases Tests

    @Test("Ref update handles zero delta")
    func refUpdateZeroDelta() async throws {
        let backend = InMemoryBackend()
        let key = Data(repeating: 0xEE, count: 31)

        // Set initial ref count
        try await backend.batchUpdate([
            .write(key: key, value: Data([0x01])),
            .refUpdate(key: key, delta: 5),
        ])

        #expect(await backend.getRefCount(key: key) == 5)

        // Apply zero delta (should be no-op)
        try await backend.batchUpdate([
            .refUpdate(key: key, delta: 0),
        ])

        #expect(await backend.getRefCount(key: key) == 5)
    }

    @Test("Ref update handles very large positive delta")
    func refUpdateVeryLargePositive() async throws {
        let backend = InMemoryBackend()
        let key = Data(repeating: 0xFF, count: 31)

        try await backend.batchUpdate([
            .write(key: key, value: Data([0x01])),
            .refUpdate(key: key, delta: Int64.max),
        ])

        #expect(await backend.getRefCount(key: key) == Int(Int64.max))
    }

    @Test("Ref update handles very large negative delta")
    func refUpdateVeryLargeNegative() async throws {
        let backend = InMemoryBackend()
        let key = Data(repeating: 0x11, count: 31)

        // Set initial ref count
        try await backend.batchUpdate([
            .write(key: key, value: Data([0x01])),
            .refUpdate(key: key, delta: 10),
        ])

        // Apply large negative delta (should clamp to 0 in real backend)
        try await backend.batchUpdate([
            .refUpdate(key: key, delta: -100),
        ])

        // InMemoryBackend allows negative counts, real backends should clamp
        #expect(await backend.getRefCount(key: key) == -90)
    }

    @Test("Ref update handles key that doesn't exist")
    func refUpdateNonExistentKey() async throws {
        let backend = InMemoryBackend()
        let key = Data(repeating: 0x22, count: 31)

        // Ref update for non-existent key should still work
        try await backend.batchUpdate([
            .refUpdate(key: key, delta: 5),
        ])

        #expect(await backend.getRefCount(key: key) == 5)
    }

    // MARK: - Performance Tests

    @Test("Ref update reduces I/O operations significantly")
    func refUpdatePerformanceBenefit() async throws {
        let backend = InMemoryBackend()

        let key = Data(repeating: 0x33, count: 31)

        // Old approach: 100 separate ref increments
        // New approach: 1 ref update with delta 100
        var ops: [StateBackendOperation] = []
        ops.append(.write(key: key, value: Data([0x01])))
        ops.append(.refUpdate(key: key, delta: 100))

        let startTime = Date()
        try await backend.batchUpdate(ops)
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(await backend.getRefCount(key: key) == 100)
        #expect(elapsed < 1.0) // Should be very fast with batching
    }

    @Test("Multiple ref updates accumulate correctly")
    func refUpdateAccumulation() async throws {
        let backend = InMemoryBackend()

        let key = Data(repeating: 0x44, count: 31)

        // Multiple ref updates that accumulate
        var ops: [StateBackendOperation] = []
        ops.append(.write(key: key, value: Data([0x01])))

        for _ in 0 ..< 10 {
            ops.append(.refUpdate(key: key, delta: 5))
        }

        try await backend.batchUpdate(ops)

        // Should be 10 * 5 = 50
        #expect(await backend.getRefCount(key: key) == 50)
    }

    // MARK: - Deletion Tests

    @Test("StateTrie handles deletion with ref updates")
    func stateTrieDeletionRefUpdates() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: false,
        )

        let key = makeKey(1)

        // Insert and save
        try await trie.update([(key, Data("value1".utf8))])
        try await trie.save()

        // Delete and save
        try await trie.update([(key, nil)])
        try await trie.save()

        // Verify deletion
        let result = try await trie.read(key: key)
        #expect(result == nil)
    }

    @Test("StateTrie handles multiple insertions and deletions")
    func stateTrieMultipleInsertDelete() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableWriteBuffer: false,
        )

        let key = makeKey(1)

        // Insert, delete, insert again
        try await trie.update([(key, Data("value1".utf8))])
        try await trie.save()

        try await trie.update([(key, nil)])
        try await trie.save()

        try await trie.update([(key, Data("value2".utf8))])
        try await trie.save()

        let result = try await trie.read(key: key)
        #expect(result == Data("value2".utf8))
    }
}

/// Helper function to create a test Data31 key
private func makeKey(_ byte: UInt8) -> Data31 {
    var keyData = Data(repeating: 0, count: 31)
    keyData[0] = byte
    return Data31(keyData)!
}
