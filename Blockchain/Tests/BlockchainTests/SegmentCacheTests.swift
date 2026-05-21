@testable import Blockchain
import Testing
import Utils

struct SegmentCacheTests {
    @Test func storesRetrievesAndTracksHitRate() {
        let cache = SegmentCache(maxSize: 2)
        let erasureRoot = Data32.random()
        let segment = Data4104(repeating: 7)

        #expect(cache.get(erasureRoot: erasureRoot, index: 0) == nil)

        cache.set(segment: segment, erasureRoot: erasureRoot, index: 0)

        #expect(cache.get(erasureRoot: erasureRoot, index: 0) == segment)

        let stats = cache.getStatistics()
        #expect(stats.hits == 1)
        #expect(stats.misses == 1)
        #expect(stats.evictions == 0)
        #expect(stats.size == 1)
        #expect(stats.hitRate == 0.5)
    }

    @Test func evictsLeastRecentlyUsedSegment() {
        let cache = SegmentCache(maxSize: 2)
        let root = Data32.random()
        let first = Data4104(repeating: 1)
        let second = Data4104(repeating: 2)
        let third = Data4104(repeating: 3)

        cache.set(segment: first, erasureRoot: root, index: 0)
        cache.set(segment: second, erasureRoot: root, index: 1)

        #expect(cache.get(erasureRoot: root, index: 0) == first)

        cache.set(segment: third, erasureRoot: root, index: 2)

        #expect(cache.get(erasureRoot: root, index: 0) == first)
        #expect(cache.get(erasureRoot: root, index: 1) == nil)
        #expect(cache.get(erasureRoot: root, index: 2) == third)
        #expect(cache.getStatistics().evictions == 1)
    }

    @Test func updatingExistingSegmentDoesNotEvict() {
        let cache = SegmentCache(maxSize: 1)
        let root = Data32.random()
        let original = Data4104(repeating: 1)
        let updated = Data4104(repeating: 2)

        cache.set(segment: original, erasureRoot: root, index: 0)
        cache.set(segment: updated, erasureRoot: root, index: 0)

        #expect(cache.get(erasureRoot: root, index: 0) == updated)
        #expect(cache.getStatistics().evictions == 0)
        #expect(cache.size == 1)
    }

    @Test func removeInvalidateAndClearSegments() {
        let cache = SegmentCache(maxSize: 4)
        let firstRoot = Data32.random()
        let secondRoot = Data32.random()

        cache.set(segment: Data4104(repeating: 1), erasureRoot: firstRoot, index: 0)
        cache.set(segment: Data4104(repeating: 2), erasureRoot: firstRoot, index: 1)
        cache.set(segment: Data4104(repeating: 3), erasureRoot: secondRoot, index: 0)

        cache.remove(erasureRoot: firstRoot, index: 0)
        #expect(cache.get(erasureRoot: firstRoot, index: 0) == nil)
        #expect(cache.get(erasureRoot: firstRoot, index: 1) == Data4104(repeating: 2))

        cache.invalidate(erasureRoot: firstRoot)
        #expect(cache.get(erasureRoot: firstRoot, index: 1) == nil)
        #expect(cache.get(erasureRoot: secondRoot, index: 0) == Data4104(repeating: 3))

        cache.clear()
        #expect(cache.size == 0)
        #expect(cache.get(erasureRoot: secondRoot, index: 0) == nil)
    }
}
