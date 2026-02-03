import Foundation

/// LRU (Least Recently Used) cache implementation
/// Optimized for caching trie nodes with automatic eviction
/// NOTE: This is a non-actor class because it's owned exclusively by StateTrie (which is an actor)
/// Making it a class avoids suspension overhead and maintains atomicity of cache operations
public final class LRUCache<Key: Hashable, Value> {
    private class CacheNode {
        let key: Key
        var value: Value
        weak var previous: CacheNode? // Prevent retain cycle
        var next: CacheNode?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    private var storage: [Key: CacheNode] = [:]
    private var head: CacheNode?
    private var tail: CacheNode?
    private let capacity: Int
    private var currentSize: Int = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// Get a value from the cache
    /// - Returns: The cached value if it exists, nil otherwise
    public func get(_ key: Key) -> Value? {
        guard let node = storage[key] else {
            return nil
        }

        // Move to head (most recently used)
        moveToHead(node: node)

        return node.value
    }

    /// Put a value into the cache
    /// - Parameters:
    ///   - key: The key to store the value under
    ///   - value: The value to cache
    public func put(_ key: Key, value: Value) {
        if let node = storage[key] {
            // Update existing node
            node.value = value
            moveToHead(node: node)
        } else {
            // Create new node
            let newNode = CacheNode(key: key, value: value)
            storage[key] = newNode
            addToHead(node: newNode)
            currentSize += 1

            // Check if we need to evict
            if currentSize > capacity {
                removeTail()
            }
        }
    }

    /// Remove a specific key from the cache
    public func remove(_ key: Key) {
        guard let node = storage[key] else {
            return
        }

        removeNode(node: node)
        storage.removeValue(forKey: key)
        currentSize -= 1
    }

    /// Clear all items from the cache
    public func removeAll() {
        storage.removeAll()
        head = nil
        tail = nil
        currentSize = 0
    }

    /// Get current cache size
    public var size: Int {
        currentSize
    }

    /// Check if cache contains a key
    public func contains(_ key: Key) -> Bool {
        storage[key] != nil
    }

    // MARK: - Private Helper Methods

    private func moveToHead(node: CacheNode) {
        if node === head {
            return
        }

        // Remove node from current position
        if let previous = node.previous {
            previous.next = node.next
        }
        if let next = node.next {
            next.previous = node.previous
        }

        if node === tail {
            tail = node.previous
        }

        // Add to head
        node.previous = nil
        node.next = head
        head?.previous = node
        head = node

        if tail == nil {
            tail = node
        }
    }

    private func addToHead(node: CacheNode) {
        node.previous = nil
        node.next = head
        head?.previous = node
        head = node

        if tail == nil {
            tail = node
        }
    }

    private func removeNode(node: CacheNode) {
        if let previous = node.previous {
            previous.next = node.next
        } else {
            head = node.next
        }

        if let next = node.next {
            next.previous = node.previous
        } else {
            tail = node.previous
        }

        node.previous = nil
        node.next = nil
    }

    private func removeTail() {
        guard let tailNode = tail else {
            return
        }

        removeNode(node: tailNode)
        storage.removeValue(forKey: tailNode.key)
        currentSize -= 1
    }

    /// Get cache statistics
    public var stats: CacheStats {
        CacheStats(size: currentSize, capacity: capacity)
    }

    public struct CacheStats: Sendable {
        public let size: Int
        public let capacity: Int
        public var utilization: Double {
            Double(size) / Double(capacity)
        }
    }
}

/// Fast statistics tracking for cache performance
/// Uses atomic operations for thread-safety without actor isolation overhead
public class CacheStatsTracker: @unchecked Sendable {
    private var hits: Int = 0
    private var misses: Int = 0
    private var evictions: Int = 0
    private let lock = NSLock()

    public func recordHit() {
        lock.lock()
        hits += 1
        lock.unlock()
    }

    public func recordMiss() {
        lock.lock()
        misses += 1
        lock.unlock()
    }

    public func recordEviction() {
        lock.lock()
        evictions += 1
        lock.unlock()
    }

    public var hitRate: Double {
        lock.lock()
        let currentHits = hits
        let currentMisses = misses
        lock.unlock()

        let total = currentHits + currentMisses
        guard total > 0 else {
            return 0
        }
        return Double(currentHits) / Double(total)
    }

    public var totalAccesses: Int {
        lock.lock()
        let total = hits + misses
        lock.unlock()
        return total
    }

    public func reset() {
        lock.lock()
        hits = 0
        misses = 0
        evictions = 0
        lock.unlock()
    }

    public var current: CacheStatistics {
        lock.lock()
        let stats = CacheStatistics(
            hits: hits,
            misses: misses,
            evictions: evictions,
            hitRate: Double(hits) / Double(max(1, hits + misses)),
            totalAccesses: hits + misses,
        )
        lock.unlock()
        return stats
    }

    public struct CacheStatistics: Sendable {
        public let hits: Int
        public let misses: Int
        public let evictions: Int
        public let hitRate: Double
        public let totalAccesses: Int

        public var description: String {
            """
            Cache Statistics:
            - Hits: \(hits)
            - Misses: \(misses)
            - Evictions: \(evictions)
            - Hit Rate: \(String(format: "%.2f%%", hitRate * 100))
            - Total Accesses: \(totalAccesses)
            """
        }
    }
}
