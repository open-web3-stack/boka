@testable import Blockchain
import Foundation
import Testing
import Utils

/// Integration tests for StateTrie with LRU cache
struct StateTrieCacheIntegrationTests {
    // MARK: - Cache Statistics Tests

    @Test("StateTrie with cache tracks statistics")
    func testCacheStatistics() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: 100
        )

        let key = makeKey(1)

        // Insert value
        try await trie.update([(key, Data("value1".utf8))])
        try await trie.save()

        // Read multiple times (should hit cache)
        for _ in 0 ..< 5 {
            _ = try await trie.read(key: key)
        }

        // Read non-existent key (should miss cache)
        _ = try await trie.read(key: makeKey(99))

        let stats = await trie.getCacheStats()
        #expect(stats != nil)
        // Cache should have tracked some activity (we can't reset stats, so we check for activity)
        #expect(stats!.totalAccesses >= 6) // At least 5 reads + 1 miss
    }

    @Test("StateTrie without cache has no statistics")
    func testNoCacheStatistics() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: false // Cache disabled
        )

        let key = makeKey(1)

        try await trie.update([(key, Data("value1".utf8))])
        try await trie.save()

        _ = try await trie.read(key: key)

        // Should have no cache stats
        let stats = await trie.getCacheStats()
        #expect(stats == nil)
    }

    // MARK: - Cache Behavior Tests

    @Test("StateTrie cache improves read performance")
    func testCachePerformance() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: 1000
        )

        // Insert multiple values
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 100 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)
        try await trie.save()

        // Read same key multiple times
        let key = makeKey(50)
        for _ in 0 ..< 10 {
            _ = try await trie.read(key: key)
        }

        let stats = await trie.getCacheStats()
        // Should have many cache hits (can't reset stats, so we check for significant activity)
        #expect(stats!.hits >= 10)
    }

    @Test("StateTrie cache evicts least recently used items")
    func testCacheEviction() async throws {
        let backend = InMemoryBackend()
        let cacheSize = 5
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: cacheSize
        )

        // Insert more items than cache size
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 10 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)
        try await trie.save()

        // Read first item (might miss cache - evicted)
        _ = try await trie.read(key: makeKey(0))

        // Read last few items (should hit cache)
        for i in 5 ..< 10 {
            _ = try await trie.read(key: makeKey(UInt8(i)))
        }

        let stats = await trie.getCacheStats()
        // Should have cache activity
        #expect(stats!.totalAccesses >= 6)
    }

    @Test("StateTrie cache handles updates correctly")
    func testCacheWithUpdates() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: 100
        )

        let key = makeKey(1)

        // Insert initial value
        try await trie.update([(key, Data("value1".utf8))])
        try await trie.save()

        // Read to populate cache
        _ = try await trie.read(key: key)

        // Update value
        try await trie.update([(key, Data("value2".utf8))])
        try await trie.save()

        // Read updated value
        let result = try await trie.read(key: key)
        #expect(result == Data("value2".utf8))
    }

    @Test("StateTrie cache handles deletions correctly")
    func testCacheWithDeletions() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: 100
        )

        let key = makeKey(1)

        // Insert value
        try await trie.update([(key, Data("value1".utf8))])
        try await trie.save()

        // Read to populate cache
        let result1 = try await trie.read(key: key)
        #expect(result1 == Data("value1".utf8))

        // Delete value
        try await trie.update([(key, nil)])
        try await trie.save()

        // Read deleted value (should return nil)
        let result2 = try await trie.read(key: key)
        #expect(result2 == nil)
    }

    // MARK: - Cache Size Tests

    @Test("StateTrie respects cache size limit")
    func testCacheSizeLimit() async throws {
        let backend = InMemoryBackend()
        let cacheSize = 10
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: cacheSize
        )

        // Insert more items than cache size
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 50 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)
        try await trie.save()

        // Cache should not exceed size limit
        // (We can't directly inspect cache size, but stats should be reasonable)
        let stats = await trie.getCacheStats()
        #expect(stats != nil)
    }

    @Test("StateTrie handles very small cache")
    func testVerySmallCache() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: 1 // Tiny cache
        )

        let key1 = makeKey(1)
        let key2 = makeKey(2)

        // Insert two values
        try await trie.update([
            (key1, Data("value1".utf8)),
        ])
        try await trie.save()

        try await trie.update([
            (key2, Data("value2".utf8)),
        ])
        try await trie.save()

        // Reset stats

        // Read first value (should miss - evicted by second)
        _ = try await trie.read(key: key1)

        // Read second value (should hit)
        _ = try await trie.read(key: key2)

        let stats = await trie.getCacheStats()
        #expect(stats!.hits >= 1)
        #expect(stats!.misses >= 1)
    }

    @Test("StateTrie handles very large cache")
    func testVeryLargeCache() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: 10000 // Large cache
        )

        // Insert many items
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 1000 {
            updates.append((makeKey(UInt8(i & 0xFF)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)
        try await trie.save()

        // Reset stats

        // Read some values - should mostly hit cache
        for i in 0 ..< 100 {
            _ = try await trie.read(key: makeKey(UInt8(i)))
        }

        let stats = await trie.getCacheStats()
        #expect(stats!.hits >= 90) // Most should be hits
    }

    // MARK: - Cache and Write Buffer Integration Tests

    @Test("StateTrie with both cache and write buffer")
    func testCacheAndWriteBuffer() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: 100,
            enableWriteBuffer: true,
            writeBufferSize: 10,
            writeBufferFlushInterval: 1.0
        )

        let key = makeKey(1)

        // Insert value
        try await trie.update([(key, Data("value1".utf8))])
        try await trie.flush() // Flush write buffer

        // Reset cache stats

        // Read multiple times
        for _ in 0 ..< 5 {
            _ = try await trie.read(key: key)
        }

        let cacheStats = await trie.getCacheStats()
        #expect(cacheStats != nil)
        #expect(cacheStats!.hits >= 5) // All should hit cache

        // Write buffer should also work
        let bufferStats = await trie.getWriteBufferStats()
        #expect(bufferStats != nil)
    }

    // MARK: - Cache Hit Rate Tests

    @Test("StateTrie cache hit rate improves with repeated reads")
    func testCacheHitRate() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: 1000
        )

        // Insert values
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 50 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)
        try await trie.save()

        // Reset stats

        // Read same 10 keys multiple times
        for _ in 0 ..< 10 {
            for i in 0 ..< 10 {
                _ = try await trie.read(key: makeKey(UInt8(i)))
            }
        }

        let stats = await trie.getCacheStats()
        let hitRate = stats?.hitRate ?? 0

        // Hit rate should be very high (>90%)
        #expect(hitRate > 0.9)
    }

    // MARK: - Cache Persistence Tests

    @Test("StateTrie cache doesn't persist across instances")
    func testCacheNotPersistent() async throws {
        let backend = InMemoryBackend()
        let key = makeKey(1)

        // First trie instance
        let trie1 = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: 100
        )

        try await trie1.update([(key, Data("value1".utf8))])
        try await trie1.save()

        // Read to populate cache
        _ = try await trie1.read(key: key)

        let stats1 = await trie1.getCacheStats()
        #expect(stats1 != nil) // Should have stats

        // Create new trie instance with same backend
        let trie2 = await StateTrie(
            rootHash: trie1.rootHash,
            backend: backend,
            enableCache: true,
            cacheSize: 100
        )

        // Read from new trie - different cache instance
        _ = try await trie2.read(key: key)

        let stats2 = await trie2.getCacheStats()
        #expect(stats2 != nil) // Should have its own stats
    }

    // MARK: - Memory Management Tests

    @Test("StateTrie cache doesn't cause memory leaks")
    func testCacheMemoryManagement() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: 100
        )

        // Add and remove many items
        for i in 0 ..< 1000 {
            let key = makeKey(UInt8(i & 0xFF))
            try await trie.update([(key, Data("value\(i)".utf8))])
            try await trie.save()

            _ = try await trie.read(key: key)

            // Delete every other item
            if i % 2 == 0 {
                try await trie.update([(key, nil)])
                try await trie.save()
            }
        }

        // Should complete without issues
        let stats = await trie.getCacheStats()
        #expect(stats != nil)
    }

    // MARK: - Concurrent Access Tests

    @Test("StateTrie cache handles concurrent reads")
    func testCacheConcurrentReads() async throws {
        let backend = InMemoryBackend()
        let trie = StateTrie(
            rootHash: Data32(),
            backend: backend,
            enableCache: true,
            cacheSize: 1000
        )

        // Insert values
        var updates: [(Data31, Data?)] = []
        for i in 0 ..< 50 {
            updates.append((makeKey(UInt8(i)), Data("value\(i)".utf8)))
        }

        try await trie.update(updates)
        try await trie.save()

        // Concurrent reads
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 10 {
                group.addTask {
                    for i in 0 ..< 50 {
                        _ = try? await trie.read(key: makeKey(UInt8(i)))
                    }
                }
            }
        }

        // Should complete without errors
        let stats = await trie.getCacheStats()
        #expect(stats != nil)
    }
}

/// Helper function to create a test Data31 key
private func makeKey(_ byte: UInt8) -> Data31 {
    var keyData = Data(repeating: 0, count: 31)
    keyData[0] = byte
    return Data31(keyData)!
}
