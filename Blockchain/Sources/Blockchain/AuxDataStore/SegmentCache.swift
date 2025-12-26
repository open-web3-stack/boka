import Foundation
import TracingUtils
import Utils

/// LRU cache for segment data to optimize repeated access
///
/// Uses NSLock for thread safety with simple operations
public final class SegmentCache: @unchecked Sendable {
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
    private let lock = NSLock()

    // Storage must be protected by lock
    private var storage: [CacheKey: CacheEntry] = [:]
    private var head: CacheKey? // Most recently used
    private var tail: CacheKey? // Least recently used
    private var hits: Int = 0
    private var misses: Int = 0
    private var evictions: Int = 0

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
        lock.lock()
        defer { lock.unlock() }

        let key = CacheKey(erasureRoot: erasureRoot, index: index)

        guard let entry = storage[key] else {
            misses += 1
            logger.debug("Cache miss: erasureRoot=\(erasureRoot.toHexString()), index=\(index)")
            return nil
        }

        // Cache hit - update access statistics and move to head (most recent)
        hits += 1
        removeFromList(key: key)

        // Update entry statistics
        var updatedEntry = entry
        updatedEntry.accessTime = .now
        updatedEntry.hitCount += 1
        storage[key] = updatedEntry

        // Add to head (most recently used)
        addToHead(key: key, entry: updatedEntry)

        logger.debug("Cache hit: erasureRoot=\(erasureRoot.toHexString()), index=\(index)")
        return entry.segment
    }

    /// Set a segment in cache
    /// - Parameters:
    ///   - segment: The segment data to cache
    ///   - erasureRoot: Erasure root identifying the data
    ///   - index: Segment index
    public func set(segment: Data4104, erasureRoot: Data32, index: Int) {
        lock.lock()
        defer { lock.unlock() }

        let key = CacheKey(erasureRoot: erasureRoot, index: index)

        // Check if we need to evict (only if this is a new key)
        if storage[key] == nil, storage.count >= maxSize {
            evictLeastRecentlyUsed()
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
        if storage[key] != nil {
            removeFromList(key: key)
        }

        // Add to head (most recently used)
        addToHead(key: key, entry: entry)

        logger.debug("Cached segment: erasureRoot=\(erasureRoot.toHexString()), index=\(index), size=\(storage.count)")
    }

    /// Remove a segment from cache
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - index: Segment index
    public func remove(erasureRoot: Data32, index: Int) {
        lock.lock()
        defer { lock.unlock() }

        let key = CacheKey(erasureRoot: erasureRoot, index: index)
        removeFromList(key: key)
        storage.removeValue(forKey: key)
    }

    /// Clear all entries from cache
    public func clear() {
        lock.lock()
        defer { lock.unlock() }

        storage.removeAll()
        head = nil
        tail = nil
        logger.info("Cache cleared")
    }

    /// Invalidate all entries for a specific erasure root
    /// - Parameter erasureRoot: Erasure root to invalidate
    public func invalidate(erasureRoot: Data32) {
        lock.lock()
        defer { lock.unlock() }

        let keysToRemove = storage.keys.filter { $0.erasureRoot == erasureRoot }
        for key in keysToRemove {
            removeFromList(key: key)
            storage.removeValue(forKey: key)
        }
        logger.info("Invalidated \(keysToRemove.count) entries for erasureRoot=\(erasureRoot.toHexString())")
    }

    /// Get cache statistics
    /// - Returns: Statistics tuple with hits, misses, evictions, and current size
    public func getStatistics() -> (hits: Int, misses: Int, evictions: Int, size: Int, hitRate: Double) {
        lock.lock()
        defer { lock.unlock() }

        let total = hits + misses
        let hitRate = total > 0 ? Double(hits) / Double(total) : 0.0
        return (
            hits: hits,
            misses: misses,
            evictions: evictions,
            size: storage.count,
            hitRate: hitRate
        )
    }

    /// Get the current cache size
    public var size: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    // MARK: - Private Methods (O(1) Doubly-Linked List Operations)

    private func addToHead(key: CacheKey, entry: CacheEntry) {
        // Create a mutable copy to update links
        var newEntry = entry
        newEntry.previousKey = nil // Head has no previous entry

        if let head {
            // Link new entry as head
            newEntry.nextKey = head

            // Update old head's previous pointer
            if var oldHeadEntry = storage[head] {
                oldHeadEntry.previousKey = key
                storage[head] = oldHeadEntry
            }
        } else {
            // This is the first entry, it's also the tail
            newEntry.nextKey = nil
            tail = key
        }

        // Store the updated entry
        storage[key] = newEntry
        head = key
    }

    private func removeFromList(key: CacheKey) {
        guard let entry = storage[key] else { return }

        // Update previous entry's next pointer
        if let prevKey = entry.previousKey {
            // Safe unwrapping with fallback for corrupted linked list
            guard var prevEntry = storage[prevKey] else {
                logger.error("Cache corruption: previous key \(prevKey.erasureRoot.toHexString()):\(prevKey.index) not found in storage")
                // Attempt to recover by removing the orphaned entry
                storage.removeValue(forKey: key)
                return
            }
            prevEntry.nextKey = entry.nextKey
            storage[prevKey] = prevEntry
        } else if head == key {
            // This was the head, update head
            head = entry.nextKey
        }

        // Update next entry's previous pointer
        if let nextKey = entry.nextKey {
            // Safe unwrapping with fallback for corrupted linked list
            guard var nextEntry = storage[nextKey] else {
                logger.error("Cache corruption: next key \(nextKey.erasureRoot.toHexString()):\(nextKey.index) not found in storage")
                // Attempt to recover by removing the orphaned entry
                storage.removeValue(forKey: key)
                return
            }
            nextEntry.previousKey = entry.previousKey
            storage[nextKey] = nextEntry
        } else if tail == key {
            // This was the tail, update tail
            tail = entry.previousKey
        }
    }

    private func evictLeastRecentlyUsed() {
        guard let tailKey = tail else { return }

        // Remove from linked list
        removeFromList(key: tailKey)

        // Remove from storage
        storage.removeValue(forKey: tailKey)
        evictions += 1

        logger.debug("Evicted LRU entry: erasureRoot=\(tailKey.erasureRoot.toHexString()), index=\(tailKey.index)")
    }
}
