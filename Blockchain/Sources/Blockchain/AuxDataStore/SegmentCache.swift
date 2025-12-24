import Foundation
import TracingUtils

/// LRU cache for segment data to optimize repeated access
public final class SegmentCache: Sendable {
    private struct CacheEntry: Sendable {
        let segment: Data4104
        let accessTime: ContinuousClock.Instant
        let hitCount: Int
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
        var accessOrder: [CacheKey]
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
                // Cache hit - update access statistics and move to end
                state.hits += 1
                let updatedEntry = CacheEntry(
                    segment: entry.segment,
                    accessTime: .now,
                    hitCount: entry.hitCount + 1
                )
                state.storage[key] = updatedEntry

                // Move to end of access order
                if let index = state.accessOrder.firstIndex(of: key) {
                    state.accessOrder.remove(at: index)
                }
                state.accessOrder.append(key)

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

            // Check if we need to evict
            if !state.storage.keys.contains(key), state.storage.count >= maxSize {
                evictLeastRecentlyUsed(state: &state)
            }

            // Add or update entry
            let entry = CacheEntry(
                segment: segment,
                accessTime: .now,
                hitCount: 0
            )
            state.storage[key] = entry

            // Update access order
            if let existingIndex = state.accessOrder.firstIndex(of: key) {
                state.accessOrder.remove(at: existingIndex)
            }
            state.accessOrder.append(key)

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
            state.storage.removeValue(forKey: key)
            if let index = state.accessOrder.firstIndex(of: key) {
                state.accessOrder.remove(at: index)
            }
        }
    }

    /// Clear all entries from cache
    public func clear() {
        lock.withLock { state in
            state.storage.removeAll()
            state.accessOrder.removeAll()
            logger.info("Cache cleared")
        }
    }

    /// Invalidate all entries for a specific erasure root
    /// - Parameter erasureRoot: Erasure root to invalidate
    public func invalidate(erasureRoot: Data32) {
        lock.withLock { state in
            let keysToRemove = state.storage.keys.filter { $0.erasureRoot == erasureRoot }
            for key in keysToRemove {
                state.storage.removeValue(forKey: key)
                if let index = state.accessOrder.firstIndex(of: key) {
                    state.accessOrder.remove(at: index)
                }
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

    // MARK: - Private Methods

    private func evictLeastRecentlyUsed(state: inout CacheState) {
        guard let oldestKey = state.accessOrder.first else { return }

        state.storage.removeValue(forKey: oldestKey)
        state.accessOrder.removeFirst()
        state.evictions += 1

        logger.debug("Evicted LRU entry: erasureRoot=\(oldestKey.erasureRoot.toHexString()), index=\(oldestKey.index)")
    }
}
