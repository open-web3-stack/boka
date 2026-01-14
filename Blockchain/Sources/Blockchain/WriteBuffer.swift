import Foundation
import Utils

/// Write buffer for batching trie updates before I/O
/// Reduces I/O operations by accumulating updates and flushing in batches
/// NOTE: This is a non-actor class because it's owned exclusively by StateTrie (which is an actor)
/// Making it a class avoids suspension overhead and maintains atomicity of batch operations
public final class WriteBuffer {
    // Count of buffered updates (we don't store the actual data since StateTrie maintains it)
    private var count: Int = 0

    // Configuration
    private let maxBufferSize: Int
    private let flushInterval: TimeInterval
    private var lastFlushTime: DispatchTime // Use monotonic clock

    // Statistics
    private var totalUpdates: Int = 0
    private var totalFlushes: Int = 0
    private var autoFlushes: Int = 0
    private var manualFlushes: Int = 0

    /// Initialize write buffer
    /// - Parameters:
    ///   - maxBufferSize: Maximum number of updates before auto-flush (default: 1000)
    ///   - flushInterval: Maximum time between flushes in seconds (default: 1.0)
    public init(maxBufferSize: Int = 1000, flushInterval: TimeInterval = 1.0) {
        self.maxBufferSize = max(1, maxBufferSize)
        self.flushInterval = max(0.1, flushInterval)
        lastFlushTime = .now()
    }

    /// Add an update to the buffer
    /// - Parameters:
    ///   - key: The key to update (not stored, only counted)
    ///   - value: The value to set (not stored, only counted)
    /// - Returns: Whether buffer should be flushed
    @discardableResult
    public func add(key _: Data31, value _: Data?) -> Bool {
        count += 1
        totalUpdates += 1

        // Check if we should auto-flush
        let shouldFlush = count >= maxBufferSize || shouldFlushByTime

        if shouldFlush {
            autoFlushes += 1
        }

        return shouldFlush
    }

    /// Clear the buffer count and mark as flushed
    /// - Returns: Whether the flush was performed (false if already empty)
    @discardableResult
    public func flush() -> Bool {
        let wasNotEmpty = count > 0
        count = 0
        lastFlushTime = .now()
        if wasNotEmpty {
            totalFlushes += 1
            manualFlushes += 1
        }
        return wasNotEmpty
    }

    /// Check if buffer is empty
    public var isEmpty: Bool {
        count == 0
    }

    /// Get current buffer size
    public var size: Int {
        count
    }

    /// Get buffer utilization (0.0 to 1.0)
    public var utilization: Double {
        Double(count) / Double(maxBufferSize)
    }

    /// Check if buffer should be flushed based on time
    public var shouldFlushByTime: Bool {
        let elapsed = lastFlushTime.upstreamTimeIntervalSinceNow
        return -elapsed >= flushInterval
    }

    /// Check if buffer should be flushed based on size
    public var shouldFlushBySize: Bool {
        count >= maxBufferSize
    }

    /// Get buffer statistics
    public var stats: WriteBufferStats {
        WriteBufferStats(
            currentSize: count,
            maxBufferSize: maxBufferSize,
            totalUpdates: totalUpdates,
            totalFlushes: totalFlushes,
            autoFlushes: autoFlushes,
            manualFlushes: manualFlushes,
            utilization: utilization
        )
    }

    /// Reset statistics (doesn't clear buffer)
    public func resetStats() {
        totalUpdates = 0
        totalFlushes = 0
        autoFlushes = 0
        manualFlushes = 0
        lastFlushTime = .now()
    }

    /// Clear buffer without flushing
    public func clear() {
        count = 0
        lastFlushTime = .now()
    }
}

/// Write buffer statistics
public struct WriteBufferStats: Sendable {
    public let currentSize: Int
    public let maxBufferSize: Int
    public let totalUpdates: Int
    public let totalFlushes: Int
    public let autoFlushes: Int
    public let manualFlushes: Int
    public let utilization: Double

    public var description: String {
        """
        Write Buffer Statistics:
        - Current Size: \(currentSize) / \(maxBufferSize)
        - Utilization: \(String(format: "%.1f%%", utilization * 100))
        - Total Updates: \(totalUpdates)
        - Total Flushes: \(totalFlushes)
        - Auto Flushes: \(autoFlushes)
        - Manual Flushes: \(manualFlushes)
        """
    }
}
