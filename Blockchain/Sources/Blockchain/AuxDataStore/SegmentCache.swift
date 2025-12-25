import Foundation
import TracingUtils

/// LRU cache for segment data to optimize repeated access
///
/// Uses a doubly-linked list implemented via Dictionary for O(1) operations
/// instead of O(N) array operations for LRU tracking.
public final class SegmentCache: Sendable {
    private struct CacheEntry: Sendable {
        let segment: Data4104
        var accessTime: ContinuousClock.Instant
        var hitCount: Int
        var previousKey: CacheKey?
        var nextKey: CacheKey?
    }

    private struct CacheKey: Hashable, Sendable {
        let erasureRoot: Data32
        let index: Int
    }

    private let maxSize: Int
    private let logger: Logger
    private let lock = OSAllocatedLock(uncheckedState: CacheState())

    private struct CacheState: Sendable {
        var storage: [CacheKey: CacheEntry]
        var head: CacheKey? // Most recently used
        var tail: CacheKey? // Least recently used
        var hits: Int
        var misses: Int
        var evictions: Int
    }

    public init(maxSize: Int = 1000, logger: Logger = .init(label: "SegmentCache")) {
        self.maxSize = maxSize
        self.logger = logger
    }

    /// Get a segment from cache
    /// - Parameters:
    ///   - segment: The segment data
    ///   - erasureRoot: Erasure root identifying the data
    ///   - index: Segment index
    public func get(segment _: Data4104, erasureRoot: Data32, index: Int) -> Data4104? {
        lock.withLock { state in
            let key = CacheKey(erasureRoot: erasureRoot, index: index)

            if let entry = state.storage[key] {
                // Cache hit - update access statistics and move to head (most recent)
                state.hits += 1

                // Remove from current position in linked list
                removeFromList(state: &state, key: key)

                // Update entry statistics
                var updatedEntry = entry
                updatedEntry.accessTime = .now
                updatedEntry.hitCount += 1

                // Add to head (most recently used)
                addToHead(state: &state, key: key, entry: updatedEntry)

                logger.debug("Cache hit: erasureRoot=\(erasureRoot.toHexString()), index=\(index)")
                return entry.segment
            } else {
                // Cache miss
                state.misses += 1
                logger.debug("Cache miss: erasureRoot=\(erasureRoot.toHexString()), index=\(index)")
                return nil
            }
        }
    }

    /// Set a segment in cache
    /// - Parameters:
    ///   - segment: The segment data to cache
    ///   - erasureRoot: Erasure root identifying the data
    ///   - index: Segment index
    public func set(segment: Data4104, erasureRoot: Data32, index: Int) {
        lock.withLock { state in
            let key = CacheKey(erasureRoot: erasureRoot, index: index)

            // Check if we need to evict (only if this is a new key)
            if state.storage[key] == nil, state.storage.count >= maxSize {
                evictLeastRecentlyUsed(state: &state)
            }

            // Create entry
            var entry = CacheEntry(
                segment: segment,
                accessTime: .now,
                hitCount: 0,
                previousKey: nil,
                nextKey: nil
            )

            // Remove from current position if updating existing
            if state.storage[key] != nil {
                removeFromList(state: &state, key: key)
            }

            // Add to head (most recently used)
            addToHead(state: &state, key: key, entry: entry)

            logger.debug("Cached segment: erasureRoot=\(erasureRoot.toHexString()), index=\(index), size=\(state.storage.count)")
        }
    }

    /// Remove a segment from cache
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - index: Segment index
    public func remove(erasureRoot: Data32, index: Int) {
        lock.withLock { state in
            let key = CacheKey(erasureRoot: erasureRoot, index: index)
            removeFromList(state: &state, key: key)
            state.storage.removeValue(forKey: key)
        }
    }

    /// Clear all entries from cache
    public func clear() {
        lock.withLock { state in
            state.storage.removeAll()
            state.head = nil
            state.tail = nil
            logger.info("Cache cleared")
        }
    }

    /// Invalidate all entries for a specific erasure root
    /// - Parameter erasureRoot: Erasure root to invalidate
    public func invalidate(erasureRoot: Data32) {
        lock.withLock { state in
            let keysToRemove = state.storage.keys.filter { $0.erasureRoot == erasureRoot }
            for key in keysToRemove {
                removeFromList(state: &state, key: key)
                state.storage.removeValue(forKey: key)
            }
            logger.info("Invalidated \(keysToRemove.count) entries for erasureRoot=\(erasureRoot.toHexString())")
        }
    }

    /// Get cache statistics
    /// - Returns: Statistics tuple with hits, misses, evictions, and current size
    public func getStatistics() -> (hits: Int, misses: Int, evictions: Int, size: Int, hitRate: Double) {
        lock.withLock { state in
            let total = state.hits + state.misses
            let hitRate = total > 0 ? Double(state.hits) / Double(total) : 0.0
            return (
                hits: state.hits,
                misses: state.misses,
                evictions: state.evictions,
                size: state.storage.count,
                hitRate: hitRate
            )
        }
    }

    /// Get the current cache size
    public var size: Int {
        lock.withLock { $0.storage.count }
    }

    // MARK: - Private Methods (O(1) Doubly-Linked List Operations)

    private func addToHead(state: inout CacheState, key: CacheKey, entry: CacheEntry) {
        // Create a mutable copy to update links
        var newEntry = entry
        newEntry.previousKey = nil // Head has no previous entry

        if let head = state.head {
            // Link new entry as head
            newEntry.nextKey = head

            // Update old head's previous pointer
            if var oldHeadEntry = state.storage[head] {
                oldHeadEntry.previousKey = key
                state.storage[head] = oldHeadEntry
            }
        } else {
            // This is the first entry, it's also the tail
            newEntry.nextKey = nil
            state.tail = key
        }

        // Store the updated entry
        state.storage[key] = newEntry
        state.head = key
    }

    private func removeFromList(state: inout CacheState, key: CacheKey) {
        guard let entry = state.storage[key] else { return }

        // Update previous entry's next pointer
        if let prevKey = entry.previousKey {
            state.storage[prevKey]?.nextKey = entry.nextKey
        } else if state.head == key {
            // This was the head, update head
            state.head = entry.nextKey
        }

        // Update next entry's previous pointer
        if let nextKey = entry.nextKey {
            state.storage[nextKey]?.previousKey = entry.previousKey
        } else if state.tail == key {
            // This was the tail, update tail
            state.tail = entry.previousKey
        }
    }

    private func evictLeastRecentlyUsed(state: inout CacheState) {
        guard let tailKey = state.tail else { return }

        // Remove from linked list
        removeFromList(state: &state, key: tailKey)

        // Remove from storage
        state.storage.removeValue(forKey: tailKey)
        state.evictions += 1

        logger.debug("Evicted LRU entry: erasureRoot=\(tailKey.erasureRoot.toHexString()), index=\(tailKey.index)")
    }
}
