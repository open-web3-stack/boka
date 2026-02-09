import Foundation
import TracingUtils

private let logger = Logger(label: "DataStoreCleanup")

/// Actor for thread-safe counters
private actor Counter {
    private var value: Int = 0
    func increment() -> Int {
        value += 1; return value
    }

    func add(_ delta: Int) -> Int {
        value += delta; return value
    }

    func get() -> Int {
        value
    }
}

/// Cleanup operations for audit and D³L entries
///
/// Handles deletion of expired entries from both RocksDB and filesystem storage
public actor DataStoreCleanup {
    private let dataStore: any DataStoreProtocol
    private let filesystemStore: FilesystemDataStore
    private var cleanupMetrics = CleanupMetrics()
    private var cleanupState = CleanupState()
    private var genesisTimestamp: Date = .init(timeIntervalSince1970: 0)

    public init(
        dataStore: any DataStoreProtocol,
        filesystemStore: FilesystemDataStore,
    ) {
        self.dataStore = dataStore
        self.filesystemStore = filesystemStore
    }

    /// Set the genesis timestamp for epoch-based calculations
    public func setGenesisTimestamp(_ genesis: Date) {
        genesisTimestamp = genesis
    }

    /// Get current cleanup metrics
    public func getMetrics() -> CleanupMetrics {
        cleanupMetrics
    }

    /// Reset cleanup metrics
    public func resetMetrics() {
        cleanupMetrics = CleanupMetrics()
    }

    // MARK: - Audit Entry Cleanup

    /// Cleanup expired audit entries (older than retention period)
    ///
    /// Uses iterator-based cleanup to avoid loading all entries into memory.
    ///
    /// - Parameter retentionEpochs: Number of epochs to retain (default: 6)
    /// - Returns: Tuple of (entries deleted, bytes reclaimed)
    public func cleanupAuditEntries(retentionEpochs: UInt32 = 6) async throws -> (entriesDeleted: Int, bytesReclaimed: Int) {
        let epochDuration: TimeInterval = 600 // 10 minutes per epoch (GP spec)
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(retentionEpochs) * epochDuration)

        let deletedCount = Counter()
        let bytesReclaimed = Counter()

        // Use iterator-based cleanup to process entries in batches
        _ = try await dataStore.cleanupAuditEntriesIteratively(
            before: cutoffDate,
            batchSize: 100,
        ) { batch in
            for entry in batch {
                // Delete from filesystem
                try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)

                // Delete from RocksDB
                try await dataStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
                try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

                _ = await deletedCount.increment()
                _ = await bytesReclaimed.add(entry.bundleSize)
            }

            // Continue processing (return true)
            return true
        }

        let finalDeletedCount = await deletedCount.get()
        let finalBytesReclaimed = await bytesReclaimed.get()

        logger.info("Cleanup: deleted \(finalDeletedCount) audit entries, reclaimed \(finalBytesReclaimed) bytes")

        return (finalDeletedCount, finalBytesReclaimed)
    }

    /// Cleanup expired audit entries (older than cutoff epoch)
    ///
    /// - Parameter cutoffEpoch: Cleanup entries from epochs before this value
    /// - Returns: Tuple of (entries deleted, bytes reclaimed)
    public func cleanupAuditEntriesBeforeEpoch(cutoffEpoch: UInt32) async throws -> (entriesDeleted: Int, bytesReclaimed: Int) {
        let startTime = Date()
        let cutoffDate = epochToTimestamp(epoch: cutoffEpoch)

        // Save state before starting cleanup
        cleanupState.auditCleanupEpoch = cutoffEpoch
        cleanupState.isInProgress = true
        cleanupState.lastCleanupTime = startTime
        try await saveCleanupState()

        let entries = try await dataStore.listAuditEntries(before: cutoffDate)

        var deletedCount = 0
        var bytesReclaimed = 0

        for entry in entries {
            // Delete from filesystem
            try await filesystemStore.deleteAuditBundle(erasureRoot: entry.erasureRoot)

            // Delete from RocksDB
            try await dataStore.deleteAuditEntry(erasureRoot: entry.erasureRoot)
            try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

            deletedCount += 1
            bytesReclaimed += entry.bundleSize
        }

        let duration = Date().timeIntervalSince(startTime)

        // Update metrics
        cleanupMetrics.lastCleanupTime = Date()
        cleanupMetrics.entriesDeletedLastRun = deletedCount
        cleanupMetrics.bytesReclaimedLastRun = bytesReclaimed
        cleanupMetrics.cleanupDuration = duration
        cleanupMetrics.totalEntriesDeleted += deletedCount
        cleanupMetrics.totalBytesReclaimed += bytesReclaimed

        // Mark cleanup as complete
        cleanupState.isInProgress = false
        try await saveCleanupState()

        logger.info(
            "Cleanup: deleted \(deletedCount) audit entries before epoch \(cutoffEpoch), reclaimed \(bytesReclaimed) bytes in \(duration)s",
        )

        return (deletedCount, bytesReclaimed)
    }

    // MARK: - D³L Entry Cleanup

    /// Cleanup expired D³L entries (older than retention period)
    ///
    /// Uses iterator-based cleanup to avoid loading all entries into memory.
    ///
    /// - Parameter retentionEpochs: Number of epochs to retain (default: 672)
    /// - Returns: Tuple of (entries deleted, segments deleted)
    public func cleanupD3LEntries(retentionEpochs: UInt32 = 672) async throws -> (entriesDeleted: Int, segmentsDeleted: Int) {
        let epochDuration: TimeInterval = 600 // 10 minutes per epoch
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(retentionEpochs) * epochDuration)

        let deletedEntries = Counter()
        let deletedSegments = Counter()

        // Use iterator-based cleanup to process entries in batches
        _ = try await dataStore.cleanupD3LEntriesIteratively(
            before: cutoffDate,
            batchSize: 100,
        ) { batch in
            for entry in batch {
                // Delete from filesystem
                try await filesystemStore.deleteD3LShards(erasureRoot: entry.erasureRoot)

                // Delete from RocksDB
                try await dataStore.deleteD3LEntry(erasureRoot: entry.erasureRoot)
                try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

                _ = await deletedEntries.increment()
                _ = await deletedSegments.add(Int(entry.segmentCount))
            }
            return true // Continue cleanup
        }

        let finalDeletedEntries = await deletedEntries.get()
        let finalDeletedSegments = await deletedSegments.get()

        logger.info("Cleanup: deleted \(finalDeletedEntries) D³L entries, \(finalDeletedSegments) segments")

        return (finalDeletedEntries, finalDeletedSegments)
    }

    /// Cleanup expired D³L entries (older than cutoff epoch)
    ///
    /// - Parameter cutoffEpoch: Cleanup entries from epochs before this value
    /// - Returns: Tuple of (entries deleted, segments deleted)
    public func cleanupD3LEntriesBeforeEpoch(cutoffEpoch: UInt32) async throws -> (entriesDeleted: Int, segmentsDeleted: Int) {
        let startTime = Date()
        let cutoffDate = epochToTimestamp(epoch: cutoffEpoch)

        // Save state before starting cleanup
        cleanupState.d3lCleanupEpoch = cutoffEpoch
        cleanupState.isInProgress = true
        cleanupState.lastCleanupTime = startTime
        try await saveCleanupState()

        let entries = try await dataStore.listD3LEntries(before: cutoffDate)

        var deletedEntries = 0
        var deletedSegments = 0

        for entry in entries {
            // Delete from filesystem
            try await filesystemStore.deleteD3LShards(erasureRoot: entry.erasureRoot)

            // Delete from RocksDB
            try await dataStore.deleteD3LEntry(erasureRoot: entry.erasureRoot)
            try await dataStore.deleteShards(erasureRoot: entry.erasureRoot)

            deletedEntries += 1
            deletedSegments += Int(entry.segmentCount)
        }

        let duration = Date().timeIntervalSince(startTime)

        // Update metrics
        cleanupMetrics.lastCleanupTime = Date()
        cleanupMetrics.entriesDeletedLastRun += deletedEntries
        cleanupMetrics.segmentsDeletedLastRun = deletedSegments
        cleanupMetrics.cleanupDuration += duration
        cleanupMetrics.totalEntriesDeleted += deletedEntries

        // Mark cleanup as complete
        cleanupState.isInProgress = false
        try await saveCleanupState()

        logger.info(
            "Cleanup: deleted \(deletedEntries) D³L entries before epoch \(cutoffEpoch), \(deletedSegments) segments in \(duration)s",
        )

        return (deletedEntries, deletedSegments)
    }

    // MARK: - State Persistence

    /// Save cleanup state to RocksDB metadata
    private func saveCleanupState() async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(cleanupState)

        // Store in RocksDB metadata with a special key
        let stateKey = Data("__cleanup_state__".utf8)
        try await dataStore.setMetadata(key: stateKey, value: data)

        logger.trace("Saved cleanup state: auditEpoch=\(cleanupState.auditCleanupEpoch), d3lEpoch=\(cleanupState.d3lCleanupEpoch)")
    }

    /// Load cleanup state from RocksDB metadata
    private func loadCleanupState() async throws {
        let stateKey = Data("__cleanup_state__".utf8)

        if let data = try await dataStore.getMetadata(key: stateKey) {
            let decoder = JSONDecoder()
            cleanupState = try decoder.decode(CleanupState.self, from: data)

            logger.debug(
                """
                Loaded cleanup state: auditEpoch=\(cleanupState.auditCleanupEpoch), \
                d3lEpoch=\(cleanupState.d3lCleanupEpoch), \
                inProgress=\(cleanupState.isInProgress)
                """,
            )
        } else {
            // No saved state found, use defaults
            cleanupState = CleanupState()
            logger.debug("No saved cleanup state found, using defaults")
        }
    }

    /// Resume incomplete cleanup if state indicates one was in progress
    public func resumeIncompleteCleanupIfNeeded() async throws {
        try await loadCleanupState()

        guard cleanupState.isInProgress else {
            logger.debug("No incomplete cleanup to resume")
            return
        }

        logger.info("Resuming incomplete cleanup from epoch \(cleanupState.auditCleanupEpoch)")

        // Resume audit cleanup
        if cleanupState.auditCleanupEpoch > 0 {
            let (deleted, bytes) = try await cleanupAuditEntriesBeforeEpoch(
                cutoffEpoch: cleanupState.auditCleanupEpoch,
            )

            logger.info("Resumed audit cleanup: deleted \(deleted) entries, \(bytes) bytes")
        }

        // Resume D³L cleanup
        if cleanupState.d3lCleanupEpoch > 0 {
            let (deleted, segments) = try await cleanupD3LEntriesBeforeEpoch(
                cutoffEpoch: cleanupState.d3lCleanupEpoch,
            )

            logger.info("Resumed D³L cleanup: deleted \(deleted) entries, \(segments) segments")
        }

        // Mark cleanup as complete
        cleanupState.isInProgress = false
        try await saveCleanupState()

        logger.info("Successfully resumed incomplete cleanup")
    }

    // MARK: - Helpers

    /// Convert epoch index to timestamp
    /// - Parameter epoch: The epoch index to convert
    /// - Returns: The timestamp for the start of the given epoch
    private func epochToTimestamp(epoch: UInt32) -> Date {
        // GP spec: 10 minutes per epoch (600 seconds)
        let epochDuration: TimeInterval = 600
        let epochStartTime = TimeInterval(epoch) * epochDuration

        // Add to genesis timestamp to get actual wall-clock time
        return genesisTimestamp.addingTimeInterval(epochStartTime)
    }
}
