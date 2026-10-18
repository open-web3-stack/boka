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

    /// Estimate payload storage assuming complete shard sets and an audit bundle copy.
    /// Excludes metadata and filesystem/database overhead; partial or duplicate
    /// shard copies can make actual usage differ.
    ///
    /// - Returns: Storage usage information
    public func getStorageUsage() async throws -> StorageUsage {
        let auditEntries = try await dataStore.listAuditEntries(before: Date())
        let d3lEntries = try await dataStore.listD3LEntries(before: Date())

        var auditBytes = 0
        for entry in auditEntries {
            auditBytes += try await estimatedAuditBytes(entry)
        }
        var d3lShardBytes = 0
        for entry in d3lEntries {
            d3lShardBytes += try await estimatedD3LBytes(entry)
        }

        let totalBytes = auditBytes + d3lShardBytes
        let entryCount = auditEntries.count + d3lEntries.count

        return StorageUsage(
            totalBytes: totalBytes,
            auditStoreBytes: auditBytes,
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
    /// - Returns: Cleanup progress with estimated reclaimed payload bytes
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
            let size = try await estimatedAuditBytes(entry)
            try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)
            try await dataStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
            try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)
            try await dataStore.deleteErasureValidatorCountIfUnused(erasureRoot: entry.erasureRoot)

            deletedCount += 1
            bytesReclaimed += size
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
    /// Processes audit entries first, then D³L entries, oldest first within each batch.
    ///
    /// - Parameter targetBytes: Target estimated payload bytes to free
    /// - Returns: Estimated reclaimed payload bytes, using the same assumptions as getStorageUsage
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
                    let size = try await self.estimatedAuditBytes(entry)

                    try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteErasureValidatorCountIfUnused(erasureRoot: entry.erasureRoot)

                    // Update counter
                    await counter.add(size)

                    let updated = await counter.get()
                    logger.trace(
                        """
                        Aggressive cleanup: deleted audit entry \(entry.erasureRoot), \
                         estimated freed payload: \(size) bytes (total: \(updated)/\(targetBytes))
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
                    let size = try await self.estimatedD3LBytes(entry)

                    try await filesystemStore.deleteD3LShards(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteD3LEntry(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)
                    try await dataStore.deleteErasureValidatorCountIfUnused(erasureRoot: entry.erasureRoot)

                    // Update counter
                    await counter.add(size)

                    let updated = await counter.get()
                    logger.trace(
                        """
                        Aggressive cleanup: deleted D³L entry \(entry.erasureRoot), \
                         estimated freed payload: \(size) bytes (total: \(updated)/\(targetBytes))
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

    private func estimatedAuditBytes(_ entry: AuditEntry) async throws -> Int {
        let validators = try await dataStore.getErasureValidatorCount(erasureRoot: entry.erasureRoot)
        let width = 2 * ErasureCodingService.originalShards(validators: validators)
        let pieces = entry.bundleSize / width + (entry.bundleSize % width == 0 ? 0 : 1)
        return entry.bundleSize + validators * 2 * pieces
    }

    private func estimatedD3LBytes(_ entry: D3LEntry) async throws -> Int {
        let validators = try await dataStore.getErasureValidatorCount(erasureRoot: entry.erasureRoot)
        let required = ErasureCodingService.originalShards(validators: validators)
        return validators * Int(entry.segmentCount) * (4104 / required)
    }
}
