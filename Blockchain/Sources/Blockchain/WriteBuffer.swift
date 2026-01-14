import Foundation
import Utils

/// Write buffer for batching trie updates before I/O
/// Reduces I/O operations by accumulating updates and flushing in batches
public actor WriteBuffer {
    // Buffered updates waiting to be flushed
    private var buffer: [(key: Data31, value: Data?)] = []

    // Configuration
    private let maxBufferSize: Int
    private let flushInterval: TimeInterval
    private var lastFlush: Date = .init()

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
    }

    /// Add an update to the buffer
    /// - Parameters:
    ///   - key: The key to update
    ///   - value: The value to set (nil for delete)
    /// - Returns: Whether buffer should be flushed
    @discardableResult
    public func add(key: Data31, value: Data?) -> Bool {
        buffer.append((key, value))
        totalUpdates += 1

        // Check if we should auto-flush
        let shouldFlush = buffer.count >= maxBufferSize ||
            Date().timeIntervalSince(lastFlush) >= flushInterval

        if shouldFlush {
            autoFlushes += 1
        }

        return shouldFlush
    }

    /// Get all buffered updates and clear the buffer
    /// - Returns: Array of buffered updates
    public func flush() -> [(key: Data31, value: Data?)] {
        let updates = buffer
        buffer.removeAll()
        lastFlush = Date()
        totalFlushes += 1
        manualFlushes += 1
        return updates
    }

    /// Check if buffer is empty
    public var isEmpty: Bool {
        buffer.isEmpty
    }

    /// Get current buffer size
    public var size: Int {
        buffer.count
    }

    /// Get buffer utilization (0.0 to 1.0)
    public var utilization: Double {
        Double(buffer.count) / Double(maxBufferSize)
    }

    /// Check if buffer should be flushed based on time
    public var shouldFlushByTime: Bool {
        Date().timeIntervalSince(lastFlush) >= flushInterval
    }

    /// Check if buffer should be flushed based on size
    public var shouldFlushBySize: Bool {
        buffer.count >= maxBufferSize
    }

    /// Get buffer statistics
    public var stats: WriteBufferStats {
        WriteBufferStats(
            currentSize: buffer.count,
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
        lastFlush = Date()
    }

    /// Clear buffer without flushing
    public func clear() {
        buffer.removeAll()
        lastFlush = Date()
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
