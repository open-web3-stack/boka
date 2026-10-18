import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "AuditBundleStore")

/// Service for storing and retrieving audit bundles with erasure coding
///
/// Per GP 14.3.1: Stores work-package + extrinsics + imports + proofs
/// - Erasure-codes the bundle into one shard per assuring validator
/// - Stores in filesystem under audit/ directory
/// - Records metadata in RocksDB
/// - Sets timestamp for retention tracking (6 epochs)
public actor AuditBundleStore {
    private let dataStore: any DataStoreProtocol
    private let filesystemStore: FilesystemDataStore
    private let erasureCoding: ErasureCodingService
    private let config: ProtocolConfigRef

    public init(
        dataStore: any DataStoreProtocol,
        filesystemStore: FilesystemDataStore,
        erasureCoding: ErasureCodingService,
        config: ProtocolConfigRef,
    ) {
        self.dataStore = dataStore
        self.filesystemStore = filesystemStore
        self.erasureCoding = erasureCoding
        self.config = config
    }

    /// Store auditable work package bundle with automatic erasure coding
    ///
    /// - Parameters:
    ///   - bundle: Complete auditable work package data
    ///   - workPackageHash: Hash of the work package
    ///   - segmentsRoot: Merkle root of segments
    /// - Returns: Erasure root for the stored bundle
    public func storeBundle(
        bundle: Data,
        workPackageHash: Data32,
        segmentsRoot: Data32,
        validatorCount: Int? = nil,
    ) async throws -> Data32 {
        let erasureCoding = await erasureCoding.forValidators(validatorCount)
        logger.debug("Storing audit bundle: workPackageHash=\(workPackageHash.toHexString()), size=\(bundle.count)")

        // Encoded bundle limit, including framing and references.
        let maxBundleSize = config.value.maxWorkBundleSize
        guard bundle.count <= maxBundleSize else {
            throw ErasureCodingStoreError.bundleTooLarge(size: bundle.count, maxSize: maxBundleSize)
        }

        // Align the bundle to the coding width for this assurer set.
        // Original size is stored in metadata to truncate padding during reconstruction
        let pieceSize = await erasureCoding.inputPieceSize
        let remainder = bundle.count % pieceSize
        let paddingNeeded = remainder == 0 ? 0 : (pieceSize - remainder)

        var paddedBundle = bundle
        if paddingNeeded > 0 {
            paddedBundle.append(Data(count: paddingNeeded))
            logger.trace("Padded bundle from \(bundle.count) to \(paddedBundle.count) bytes")
        }

        // Erasure-code the padded bundle
        let shards = try await erasureCoding.encodeBlob(paddedBundle)

        // Calculate erasure root
        let erasureRoot = try await erasureCoding.calculateErasureRoot(
            segmentsRoot: segmentsRoot,
            shards: shards,
        )
        try await dataStore.setErasureValidatorCount(erasureRoot: erasureRoot, count: erasureCoding.validatorCount)

        // Store bundle in filesystem (for quick retrieval)
        try await filesystemStore.storeAuditBundle(erasureRoot: erasureRoot, data: bundle)

        // Store shards in RocksDB (for distributed access)
        let shardTuples = shards.enumerated().map { index, data in
            (index: UInt16(index), data: data)
        }
        try await dataStore.storeShards(shards: shardTuples, erasureRoot: erasureRoot)

        // Store metadata
        try await dataStore.setTimestamp(erasureRoot: erasureRoot, timestamp: Date())
        try await dataStore.setAuditEntry(
            workPackageHash: workPackageHash,
            erasureRoot: erasureRoot,
            segmentsRoot: segmentsRoot,
            bundleSize: bundle.count,
            timestamp: Date(),
        )
        try await dataStore.set(erasureRoot: erasureRoot, forSegmentRoot: segmentsRoot)

        logger.info("Stored audit bundle: erasureRoot=\(erasureRoot.toHexString())")

        return erasureRoot
    }

    /// Retrieve audit bundle by erasure root
    ///
    /// - Parameter erasureRoot: Erasure root identifying the bundle
    /// - Returns: Bundle data or nil if not found
    public func getBundle(erasureRoot: Data32) async throws -> Data? {
        // A complete bundle needs no coding metadata or reconstruction.
        if let bundle = try await filesystemStore.getAuditBundle(erasureRoot: erasureRoot) {
            return bundle
        }

        // Fallback to reconstruction from shards
        let count = try await dataStore.getErasureValidatorCount(erasureRoot: erasureRoot)
        let erasureCoding = await erasureCoding.forValidators(count)
        let requiredShardCount = await erasureCoding.requiredShardCount
        let indices = try await dataStore.getAvailableShardIndices(erasureRoot: erasureRoot)
        guard indices.count >= requiredShardCount else {
            logger.warning("Insufficient shards for reconstruction: \(indices.count)/\(requiredShardCount)")
            return nil
        }

        let shards = try await dataStore.getShards(erasureRoot: erasureRoot, shardIndices: Array(indices.prefix(requiredShardCount)))

        // Determine original size from audit metadata
        guard let auditEntry = try await dataStore.getAuditEntry(erasureRoot: erasureRoot) else {
            return nil
        }

        // Reconstruct
        let reconstructed = try await erasureCoding.reconstruct(
            shards: shards,
            originalLength: auditEntry.bundleSize,
        )

        logger.debug("Reconstructed audit bundle from \(shards.count) shards")

        return reconstructed
    }
}
