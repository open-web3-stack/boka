@testable import Blockchain
import Foundation
import Testing
import Utils

struct WriteBufferTests {
    @Test func clampsConfigurationAndTracksUtilization() {
        let buffer = WriteBuffer(maxBufferSize: 0, flushInterval: 0)

        #expect(buffer.isEmpty)
        #expect(buffer.stats.maxBufferSize == 1)

        let shouldFlush = buffer.add(key: Data31(), value: Data([1]))

        #expect(shouldFlush)
        #expect(buffer.shouldFlushBySize)
        #expect(buffer.size == 1)
        #expect(buffer.utilization == 1.0)
        #expect(buffer.stats.totalUpdates == 1)
        #expect(buffer.stats.autoFlushes == 1)
    }

    @Test func flushClearsBufferAndCountsOnlyNonEmptyFlushes() {
        let buffer = WriteBuffer(maxBufferSize: 3)

        buffer.add(key: Data31(), value: nil)
        buffer.add(key: Data31.random(), value: Data([2]))

        #expect(buffer.flush())
        #expect(buffer.isEmpty)
        #expect(buffer.stats.totalFlushes == 1)
        #expect(buffer.stats.manualFlushes == 1)

        #expect(!buffer.flush())
        #expect(buffer.stats.totalFlushes == 1)
        #expect(buffer.stats.manualFlushes == 1)
    }

    @Test func clearDoesNotCountAsFlush() {
        let buffer = WriteBuffer(maxBufferSize: 3)

        buffer.add(key: Data31(), value: Data([1]))
        buffer.clear()

        #expect(buffer.isEmpty)
        #expect(buffer.stats.totalUpdates == 1)
        #expect(buffer.stats.totalFlushes == 0)
    }

    @Test func resetStatsKeepsCurrentBufferContents() {
        let buffer = WriteBuffer(maxBufferSize: 5)

        buffer.add(key: Data31(), value: Data([1]))
        buffer.flush()
        buffer.add(key: Data31.random(), value: Data([2]))

        buffer.resetStats()

        #expect(buffer.size == 1)
        #expect(buffer.stats.totalUpdates == 0)
        #expect(buffer.stats.totalFlushes == 0)
        #expect(buffer.stats.autoFlushes == 0)
        #expect(buffer.stats.manualFlushes == 0)
    }

    @Test func flushesAfterTimeInterval() async throws {
        let buffer = WriteBuffer(maxBufferSize: 10, flushInterval: 0.1)

        try await Task.sleep(for: .milliseconds(120))

        #expect(buffer.shouldFlushByTime)
        #expect(buffer.add(key: Data31(), value: Data([1])))
        #expect(buffer.stats.autoFlushes == 1)
    }
}
