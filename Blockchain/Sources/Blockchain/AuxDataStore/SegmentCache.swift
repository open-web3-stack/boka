import Foundation
import Synchronization
import TracingUtils
import Utils

/// LRU cache for segment data
///
/// Thread-safety: @unchecked Sendable is safe here because:
/// - All mutable state is protected by a Mutex (Swift Synchronization)
/// - State modifications only occur within Mutex.withLock critical sections
/// - Lock provides exclusive access to prevent data races
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

    private struct CacheState: Sendable {
        var storage: [CacheKey: CacheEntry] = [:]
        var head: CacheKey? // Most recently used
        var tail: CacheKey? // Least recently used
        var hits: Int = 0
        var misses: Int = 0
        var evictions: Int = 0
    }

    private let maxSize: Int
    private let logger: Logger
    private let state = Mutex(CacheState())

    public init(maxSize: Int = 1000, logger: Logger = .init(label: "SegmentCache")) {
        self.maxSize = maxSize
        self.logger = logger
    }

    /// Get a segment from cache
    public func get(erasureRoot: Data32, index: Int) -> Data4104? {
        state.withLock { state in
            let key = CacheKey(erasureRoot: erasureRoot, index: index)

            guard let entry = state.storage[key] else {
                state.misses += 1
                logger.debug("Cache miss: erasureRoot=\(erasureRoot.toHexString()), index=\(index)")
                return nil
            }

            // Cache hit - update access time and move to head
            state.hits += 1
            removeFromList(key: key, state: &state)

            var updatedEntry = entry
            updatedEntry.accessTime = .now
            updatedEntry.hitCount += 1
            state.storage[key] = updatedEntry

            addToHead(key: key, entry: updatedEntry, state: &state)

            logger.debug("Cache hit: erasureRoot=\(erasureRoot.toHexString()), index=\(index)")
            return entry.segment
        }
    }

    /// Set a segment in cache
    public func set(segment: Data4104, erasureRoot: Data32, index: Int) {
        state.withLock { state in
            let key = CacheKey(erasureRoot: erasureRoot, index: index)

            if state.storage[key] == nil, state.storage.count >= maxSize {
                evictLeastRecentlyUsed(state: &state)
            }

            let entry = CacheEntry(
                segment: segment,
                accessTime: .now,
                hitCount: 0,
                previousKey: nil,
                nextKey: nil
            )

            if state.storage[key] != nil {
                removeFromList(key: key, state: &state)
            }

            addToHead(key: key, entry: entry, state: &state)

            logger.debug("Cached segment: erasureRoot=\(erasureRoot.toHexString()), index=\(index), size=\(state.storage.count)")
        }
    }

    /// Remove a segment from cache
    public func remove(erasureRoot: Data32, index: Int) {
        state.withLock { state in
            let key = CacheKey(erasureRoot: erasureRoot, index: index)
            removeFromList(key: key, state: &state)
            state.storage.removeValue(forKey: key)
        }
    }

    /// Clear all entries from cache
    public func clear() {
        state.withLock { state in
            state.storage.removeAll()
            state.head = nil
            state.tail = nil
            logger.info("Cache cleared")
        }
    }

    /// Invalidate all entries for a specific erasure root
    public func invalidate(erasureRoot: Data32) {
        state.withLock { state in
            let keysToRemove = state.storage.keys.filter { $0.erasureRoot == erasureRoot }
            for key in keysToRemove {
                removeFromList(key: key, state: &state)
                state.storage.removeValue(forKey: key)
            }
            logger.info("Invalidated \(keysToRemove.count) entries for erasureRoot=\(erasureRoot.toHexString())")
        }
    }

    /// Get cache statistics
    public func getStatistics() -> (hits: Int, misses: Int, evictions: Int, size: Int, hitRate: Double) {
        state.withLock { state in
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
        state.withLock { $0.storage.count }
    }

    // MARK: - Private Methods (O(1) Doubly-Linked List)

    private func addToHead(key: CacheKey, entry: CacheEntry, state: inout CacheState) {
        var newEntry = entry
        newEntry.previousKey = nil

        if let head = state.head {
            newEntry.nextKey = head
            if var oldHeadEntry = state.storage[head] {
                oldHeadEntry.previousKey = key
                state.storage[head] = oldHeadEntry
            }
        } else {
            newEntry.nextKey = nil
            state.tail = key
        }

        state.storage[key] = newEntry
        state.head = key
    }

    private func removeFromList(key: CacheKey, state: inout CacheState) {
        guard let entry = state.storage[key] else { return }

        if let prevKey = entry.previousKey {
            guard var prevEntry = state.storage[prevKey] else {
                logger.error("Cache corruption: previous key \(prevKey.erasureRoot.toHexString()):\(prevKey.index) not found")
                state.storage.removeValue(forKey: key)
                return
            }
            prevEntry.nextKey = entry.nextKey
            state.storage[prevKey] = prevEntry
        } else if state.head == key {
            state.head = entry.nextKey
        }

        if let nextKey = entry.nextKey {
            guard var nextEntry = state.storage[nextKey] else {
                logger.error("Cache corruption: next key \(nextKey.erasureRoot.toHexString()):\(nextKey.index) not found")
                state.storage.removeValue(forKey: key)
                return
            }
            nextEntry.previousKey = entry.previousKey
            state.storage[nextKey] = nextEntry
        } else if state.tail == key {
            state.tail = entry.previousKey
        }
    }

    private func evictLeastRecentlyUsed(state: inout CacheState) {
        guard let tailKey = state.tail else { return }

        removeFromList(key: tailKey, state: &state)
        state.storage.removeValue(forKey: tailKey)
        state.evictions += 1

        logger.debug("Evicted LRU entry: erasureRoot=\(tailKey.erasureRoot.toHexString()), index=\(tailKey.index)")
    }
}
