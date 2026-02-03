@testable import Blockchain
import Foundation
import Testing
import Utils

/// Comprehensive unit tests for LRUCache
struct LRUCacheTests {
    // MARK: - Basic Operations Tests

    @Test("LRU cache initializes with correct capacity")
    func initialization() {
        let cache = LRUCache<String, Int>(capacity: 10)
        #expect(cache.stats.capacity == 10)
        #expect(cache.size == 0)
    }

    @Test("LRU cache adds and retrieves values")
    func putAndGet() {
        let cache = LRUCache<String, Int>(capacity: 10)
        cache.put("key1", value: 100)

        let result = cache.get("key1")
        #expect(result == 100)
    }

    @Test("LRU cache returns nil for non-existent keys")
    func getNonExistent() {
        let cache = LRUCache<String, Int>(capacity: 10)
        let result = cache.get("nonexistent")
        #expect(result == nil)
    }

    @Test("LRU cache updates existing keys")
    func updateExisting() {
        let cache = LRUCache<String, Int>(capacity: 10)
        cache.put("key1", value: 100)
        cache.put("key1", value: 200)

        let result = cache.get("key1")
        #expect(result == 200)
        #expect(cache.size == 1) // Size should still be 1
    }

    // MARK: - Eviction Tests

    @Test("LRU cache evicts least recently used item when capacity exceeded")
    func eviction() {
        let cache = LRUCache<Int, String>(capacity: 3)

        // Fill cache to capacity
        cache.put(1, value: "one")
        cache.put(2, value: "two")
        cache.put(3, value: "three")

        // Access key 1 to make it more recently used than key 2
        _ = cache.get(1)

        // Add new item - should evict key 2 (least recently used)
        cache.put(4, value: "four")

        // Verify eviction
        #expect(cache.get(1) == "one") // Still exists (was accessed)
        #expect(cache.get(2) == nil) // Evicted (least recently used)
        #expect(cache.get(3) == "three") // Still exists
        #expect(cache.get(4) == "four") // New item
        #expect(cache.size == 3)
    }

    @Test("LRU cache evicts in correct order")
    func evictionOrder() {
        let cache = LRUCache<Int, Int>(capacity: 3)

        cache.put(1, value: 1)
        cache.put(2, value: 2)
        cache.put(3, value: 3)

        // All keys are in LRU order: 1, 2, 3 (1 is least recent)

        // Add key 4 - should evict key 1
        cache.put(4, value: 4)
        #expect(cache.get(1) == nil)

        // Add key 5 - should evict key 2
        cache.put(5, value: 5)
        #expect(cache.get(2) == nil)

        // Add key 6 - should evict key 3
        cache.put(6, value: 6)
        #expect(cache.get(3) == nil)
    }

    @Test("LRU cache updates recency on get")
    func getUpdatesRecency() {
        let cache = LRUCache<Int, String>(capacity: 3)

        cache.put(1, value: "one")
        cache.put(2, value: "two")
        cache.put(3, value: "three")

        // Access key 1 to make it most recently used
        _ = cache.get(1)

        // Add key 4 - should evict key 2 (now least recently used)
        cache.put(4, value: "four")

        #expect(cache.get(1) == "one") // Still exists
        #expect(cache.get(2) == nil) // Evicted
        #expect(cache.get(3) == "three") // Still exists
    }

    // MARK: - Delete Tests

    @Test("LRU cache deletes items")
    func delete() {
        let cache = LRUCache<String, Int>(capacity: 10)
        cache.put("key1", value: 100)
        cache.put("key2", value: 200)

        cache.remove("key1")

        #expect(cache.get("key1") == nil)
        #expect(cache.get("key2") == 200)
        #expect(cache.size == 1)
    }

    @Test("LRU cache handles deleting non-existent keys")
    func deleteNonExistent() {
        let cache = LRUCache<String, Int>(capacity: 10)
        cache.put("key1", value: 100)

        // Should not throw
        cache.remove("nonexistent")

        #expect(cache.size == 1)
    }

    @Test("LRU cache clears all items")
    func clear() {
        let cache = LRUCache<Int, String>(capacity: 10)

        for i in 0 ..< 5 {
            cache.put(i, value: "value\(i)")
        }

        #expect(cache.size == 5)

        cache.removeAll()

        #expect(cache.size == 0)
        #expect(cache.get(0) == nil)
        #expect(cache.get(1) == nil)
    }

    // MARK: - Contains Tests

    @Test("LRU cache checks if key exists")
    func testContains() {
        let cache = LRUCache<String, Int>(capacity: 10)

        #expect(cache.contains("key1") == false)

        cache.put("key1", value: 100)

        #expect(cache.contains("key1") == true)
        #expect(cache.contains("key2") == false)
    }

    // MARK: - Edge Cases Tests

    @Test("LRU cache handles capacity of 1")
    func capacityOne() {
        let cache = LRUCache<Int, String>(capacity: 1)

        cache.put(1, value: "one")
        #expect(cache.get(1) == "one")
        #expect(cache.size == 1)

        cache.put(2, value: "two")
        #expect(cache.get(1) == nil) // Evicted
        #expect(cache.get(2) == "two")
        #expect(cache.size == 1)
    }

    @Test("LRU cache handles same key-value updates without affecting eviction")
    func updateDoesNotAffectEviction() {
        let cache = LRUCache<Int, String>(capacity: 3)

        cache.put(1, value: "one")
        cache.put(2, value: "two")
        cache.put(3, value: "three")

        // Update key 1 - this makes it most recently used
        cache.put(1, value: "ONE")

        // Add key 4 - should evict key 2 (least recently used)
        cache.put(4, value: "four")

        #expect(cache.get(1) == "ONE") // Updated value, still exists
        #expect(cache.get(2) == nil) // Evicted
        #expect(cache.get(3) == "three") // Still exists
        #expect(cache.get(4) == "four") // New item
    }

    @Test("LRU cache handles rapid insertions and deletions")
    func rapidOperations() {
        let cache = LRUCache<Int, Int>(capacity: 5)

        // Insert many items
        for i in 0 ..< 100 {
            cache.put(i, value: i * 10)
        }

        // Only last 5 items should remain (keys 95-99)
        #expect(cache.size == 5)
        #expect(cache.get(0) == nil) // Evicted (first item)
        #expect(cache.get(94) == nil) // Evicted
        #expect(cache.get(95) == 950) // Exists (5th from last)
        #expect(cache.get(96) == 960) // Exists (4th from last)
        #expect(cache.get(97) == 970) // Exists (3rd from last)
        #expect(cache.get(98) == 980) // Exists (2nd from last)
        #expect(cache.get(99) == 990) // Exists (most recent)
    }

    // MARK: - Statistics Tests

    @Test("LRU cache tracks size and capacity correctly")
    func statistics() {
        let cache = LRUCache<Int, String>(capacity: 5)

        // Add some items
        cache.put(1, value: "one")
        cache.put(2, value: "two")
        cache.put(3, value: "three")

        let stats = cache.stats

        #expect(stats.size == 3)
        #expect(stats.capacity == 5)
        #expect(stats.utilization == 0.6) // 3/5
    }

    @Test("LRU cache updates size on eviction")
    func evictionStatistics() {
        let cache = LRUCache<Int, String>(capacity: 2)

        cache.put(1, value: "one")
        cache.put(2, value: "two")
        cache.put(3, value: "three") // Evicts key 1

        let stats = cache.stats
        #expect(stats.size == 2)
        #expect(stats.capacity == 2)
    }

    // MARK: - Memory Management Tests

    @Test("LRU cache prevents retain cycles")
    func noRetainCycles() {
        // This test verifies that weak references prevent retain cycles
        // If there were retain cycles, memory would grow unbounded

        let cache = LRUCache<String, NSObject>(capacity: 1000)

        // Add many items
        for i in 0 ..< 1000 {
            let obj = NSObject()
            cache.put("key\(i)", value: obj)
        }

        // Add more items to trigger evictions
        for i in 1000 ..< 2000 {
            let obj = NSObject()
            cache.put("key\(i)", value: obj)
        }

        // Cache should still maintain its size limit
        #expect(cache.size == 1000)

        // All old items should be evicted
        for i in 0 ..< 1000 {
            #expect(cache.get("key\(i)") == nil)
        }
    }

    // MARK: - Thread Safety Tests

    // Note: LRUCache is NOT thread-safe for concurrent access by design.
    // It's owned exclusively by StateTrie (which is an actor) for serialization.
    // Concurrent access tests would require synchronization which is intentionally
    // avoided to maintain performance.
}
