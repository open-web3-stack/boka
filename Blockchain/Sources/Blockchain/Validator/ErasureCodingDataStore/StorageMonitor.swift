import Foundation
import TracingUtils

private let logger = Logger(label: "StorageMonitor")

/// Actor for thread-safe counters
private actor Counter {
    private var value: Int = 0

    func add(_ amount: Int) {
        value += amount
    }

    func get() -> Int {
        value
    }
}

/// Service for monitoring storage usage and performing cleanup operations
public actor StorageMonitor {
    private let dataStore: any DataStoreProtocol
    private let filesystemStore: FilesystemDataStore
    private let cleanupService: DataStoreCleanup

    public init(
        dataStore: any DataStoreProtocol,
        filesystemStore: FilesystemDataStore,
        cleanupService: DataStoreCleanup,
    ) {
        self.dataStore = dataStore
        self.filesystemStore = filesystemStore
        self.cleanupService = cleanupService
    }

    /// Get storage usage statistics
    ///
    /// - Returns: Storage usage information
    public func getStorageUsage() async throws -> StorageUsage {
        let auditEntries = try await dataStore.listAuditEntries(before: Date())
        let d3lEntries = try await dataStore.listD3LEntries(before: Date())

        let auditBundleBytes = auditEntries.reduce(into: 0) { $0 += $1.bundleSize }
        let auditShardBytes = auditEntries.count * 1023 * 684 // 1023 shards per entry

        let d3lShardBytes = d3lEntries.reduce(into: 0) { $0 += Int($1.segmentCount) * 4104 }

        let totalBytes = auditBundleBytes + auditShardBytes + d3lShardBytes
        let entryCount = auditEntries.count + d3lEntries.count

        return StorageUsage(
            totalBytes: totalBytes,
            auditStoreBytes: auditBundleBytes + auditShardBytes,
            d3lStoreBytes: d3lShardBytes,
            entryCount: entryCount,
            auditEntryCount: auditEntries.count,
            d3lEntryCount: d3lEntries.count,
        )
    }

    /// Incremental cleanup for large datasets
    ///
    /// Processes data in batches to avoid blocking, saving progress checkpoints.
    ///
    /// - Parameters:
    ///   - batchSize: Maximum number of entries to process per call
    ///   - retentionEpochs: Number of epochs to retain
    /// - Returns: Cleanup progress and statistics
    public func incrementalCleanup(
        batchSize: Int = 100,
        retentionEpochs: UInt32 = 6,
    ) async throws -> IncrementalCleanupProgress {
        let epochDuration: TimeInterval = 600 // 10 minutes per epoch
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(retentionEpochs) * epochDuration)

        let entries = try await dataStore.listAuditEntries(before: cutoffDate)

        let totalCount = entries.count
        let batch = Array(entries.prefix(batchSize))

        var deletedCount = 0
        var bytesReclaimed = 0

        for entry in batch {
            try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)
            try await dataStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
            try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

            deletedCount += 1
            bytesReclaimed += entry.bundleSize
        }

        return IncrementalCleanupProgress(
            totalEntries: totalCount,
            processedEntries: deletedCount,
            remainingEntries: max(0, totalCount - deletedCount),
            bytesReclaimed: bytesReclaimed,
            isComplete: totalCount <= batchSize,
        )
    }

    /// Aggressive cleanup when under storage pressure
    ///
    /// Deletes young data if necessary to free up space.
    /// Uses priority queue to delete oldest and largest entries first.
    ///
    /// - Parameter targetBytes: Target bytes to free (will attempt to free at least this much)
    /// - Returns: Number of bytes actually reclaimed
    public func aggressiveCleanup(targetBytes: Int) async throws -> Int {
        // Use a local actor to protect the shared counter
        actor Counter {
            private var value: Int = 0

            func add(_ amount: Int) {
                value += amount
            }

            func get() -> Int {
                value
            }
        }

        let counter = Counter()

        // Use iterative cleanup to avoid loading all entries into memory at once
        // Process audit entries first (they're older and smaller)
        _ = try await dataStore.cleanupAuditEntriesIteratively(
            before: Date(),
            batchSize: 50, // Smaller batch size to limit memory usage
        ) { batch in
            // Sort batch by timestamp (oldest first) within this batch only
            let sortedBatch = batch.sorted { $0.timestamp < $1.timestamp }

            for entry in sortedBatch {
                // Check if we've met the target
                let current = await counter.get()
                guard current < targetBytes else {
                    // Early termination - return false to stop iteration
                    return false
                }

                do {
                    let size = entry.bundleSize + 1023 * 684 // 1023 shards per entry

                    try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

                    // Update counter
                    await counter.add(size)

                    let updated = await counter.get()
                    logger.trace(
                        """
                        Aggressive cleanup: deleted audit entry \(entry.erasureRoot), \
                        freed \(size) bytes (total: \(updated)/\(targetBytes))
                        """,
                    )
                } catch {
                    logger.warning("Failed to delete audit entry \(entry.erasureRoot): \(error)")
                }
            }

            // Continue to next batch
            let currentTotal = await counter.get()
            return currentTotal < targetBytes
        }

        // If we haven't met the target yet, process D³L entries
        let currentTotal = await counter.get()
        guard currentTotal < targetBytes else {
            logger.warning("Aggressive cleanup: reclaimed \(currentTotal) bytes (target: \(targetBytes))")
            return currentTotal
        }

        _ = try await dataStore.cleanupD3LEntriesIteratively(
            before: Date(),
            batchSize: 50, // Smaller batch size to limit memory usage
        ) { batch in
            // Sort batch by timestamp (oldest first) within this batch only
            let sortedBatch = batch.sorted { $0.timestamp < $1.timestamp }

            for entry in sortedBatch {
                // Check if we've met the target
                let current = await counter.get()
                guard current < targetBytes else {
                    // Early termination - return false to stop iteration
                    return false
                }

                do {
                    let size = Int(entry.segmentCount) * 4104

                    try await filesystemStore.deleteD3LShards(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteD3LEntry(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

                    // Update counter
                    await counter.add(size)

                    let updated = await counter.get()
                    logger.trace(
                        """
                        Aggressive cleanup: deleted D³L entry \(entry.erasureRoot), \
                        freed \(size) bytes (total: \(updated)/\(targetBytes))
                        """,
                    )
                } catch {
                    logger.warning("Failed to delete D³L entry \(entry.erasureRoot): \(error)")
                }
            }

            // Continue to next batch if we haven't met target
            let currentTotal = await counter.get()
            return currentTotal < targetBytes
        }

        let finalTotal = await counter.get()
        logger.warning("Aggressive cleanup: reclaimed \(finalTotal) bytes (target: \(targetBytes))")

        return finalTotal
    }
}
