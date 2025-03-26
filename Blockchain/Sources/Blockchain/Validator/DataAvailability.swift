import Codec
import Foundation
import Synchronization
import TracingUtils
import Utils

/// Errors that can occur in the DataAvailability system
public enum DataAvailabilityError: Error {
    /// Failed to store data in the data store
    case storeError
    /// Failed to retrieve data from the data store
    case retrievalError
    /// Failed to erasure code data
    case erasureCodingError
    /// Failed to distribute data
    case distributionError
    /// The requested segment was not found
    case segmentNotFound
    /// The segments root mapping was not found
    case segmentsRootMappingNotFound
    /// Invalid segment index
    case invalidSegmentIndex
    /// Invalid erasure root
    case invalidErasureRoot
    /// Invalid segments root
    case invalidSegmentsRoot
    /// Invalid data length
    case invalidDataLength
}

/// Enum defining the types of data availability stores
public enum DataAvailabilityStore: String, Sendable {
    /// Store for imported segments (long-term storage)
    case imports
    /// Store for audit data (short-term storage)
    case audits
}

/// DataAvailability service responsible for managing the storage, distribution, and retrieval
/// of data in the blockchain system.
///
/// As per GP 14.3.1:
/// Guarantors are required to erasure-code and distribute two data sets:
/// 1. Auditable work-package containing the encoded work-package, extrinsic data and self-justifying
///    imported segments (short-term Audit store)
/// 2. Exported-segments data together with the Paged-Proofs metadata (long-term store)
///
/// Items in the first store are kept until finality of the block in which the availability of the
/// work-result's work-package is assured. Items in the second store are kept for a minimum of 28 days
/// (672 complete epochs) following the reporting of the work-report.
public final class DataAvailability: ServiceBase2, @unchecked Sendable {
    /// The blockchain data provider
    private let dataProvider: BlockchainDataProvider
    /// The data store for general blockchain data
    private let dataStore: DataStore

    /// Constants for data retention
    private enum RetentionPeriods {
        /// Retention period for audit store (until finality, approximated as 1 hour)
        static let auditStore: TimeInterval = 60 * 60
        /// Retention period for import store (28 days = 672 epochs)
        static let importStore: TimeInterval = 60 * 60 * 24 * 28
    }

    /// Initialize the DataAvailability service
    /// - Parameters:
    ///   - config: The protocol configuration
    ///   - eventBus: The event bus for publishing events
    ///   - scheduler: The scheduler for scheduling tasks
    ///   - dataProvider: The blockchain data provider
    ///   - dataStore: The data store for general blockchain data
    public init(
        config: ProtocolConfigRef,
        eventBus: EventBus,
        scheduler: Scheduler,
        dataProvider: BlockchainDataProvider,
        dataStore: DataStore
    ) async {
        self.dataProvider = dataProvider
        self.dataStore = dataStore

        super.init(id: "DataAvailability", config: config, eventBus: eventBus, scheduler: scheduler)

        // Schedule regular purging of old data
        scheduleForNextEpoch("DataAvailability.scheduleForNextEpoch") { [weak self] epoch in
            await self?.purge(epoch: epoch)
        }
    }

    /// Purge old data from the data availability stores
    /// - Parameter epoch: The current epoch index
    public func purge(epoch _: EpochIndex) async {
        // GP 14.3.1
        // Guarantors are required to erasure-code and distribute two data sets: one blob, the auditable work-package containing
        // the encoded work-package, extrinsic data and self-justifying imported segments which is placed in the short-term Audit
        // da store and a second set of exported-segments data together with the Paged-Proofs metadata. Items in the first store
        // are short-lived; assurers are expected to keep them only until finality of the block in which the availability of the work-
        // result’s work-package is assured. Items in the second, meanwhile, are long-lived and expected to be kept for a minimum
        // of 28 days (672 complete epochs) following the reporting of the work-report.
    }

    /// Fetch segments from the data availability system
    /// - Parameters:
    ///   - segments: The segment specifications to retrieve
    ///   - segmentsRootMappings: Optional mappings from work package hash to segments root
    /// - Returns: The retrieved segments
    public func fetchSegment(
        segments: [WorkItem.ImportedDataSegment],
        segmentsRootMappings: SegmentsRootMappings? = nil
    ) async throws -> [Data4104] {
        // TODO: Implement segment fetching from the appropriate store
        // 1. Determine which store to fetch from based on segment type
        // 2. Resolve segment roots from mappings if needed
        // 3. Retrieve segments from the data store
        // 4. Verify segment integrity
        // 5. Return the fetched segments
        try await dataStore.fetchSegment(segments: segments, segmentsRootMappings: segmentsRootMappings)
    }

    /// Export segments to the data availability system
    /// - Parameters:
    ///   - data: The segments to export
    ///   - erasureRoot: The erasure root to associate with the segments
    /// - Returns: The segments root
    public func exportSegments(data: [Data4104], erasureRoot: Data32) async throws -> Data32 {
        // TODO: Implement segment export to the import store
        // 1. Erasure code the segments if needed
        // 2. Calculate the segments root
        // 3. Store segments in the import store
        // 4. Return the segments root
        let segmentRoot = Merklization.constantDepthMerklize(data.map(\.data))

        for (index, data) in data.enumerated() {
            try await dataStore.set(data: data, erasureRoot: erasureRoot, index: UInt16(index))
        }

        return segmentRoot
    }

    /// Export a work package bundle to the data availability system
    /// - Parameter bundle: The bundle to export
    /// - Returns: The erasure root and length of the bundle
    public func exportWorkpackageBundle(bundle _: WorkPackageBundle) async throws -> (erasureRoot: Data32, length: DataLength) {
        // TODO: Implement work package bundle export to the audit store
        // 1. Serialize the bundle
        // 2. Calculate the erasure root and length
        // 3. Store the bundle in the audit store
        // 4. Return the erasure root and length
        throw DataAvailabilityError.storeError
    }

    /// Verify that a segment belongs to an erasure root
    /// - Parameters:
    ///   - segment: The segment to verify
    ///   - index: The index of the segment
    ///   - erasureRoot: The erasure root to verify against
    ///   - proof: The Merkle proof for the segment
    /// - Returns: True if the segment is valid
    public func verifySegment(segment _: Data4104, index _: UInt16, erasureRoot _: Data32, proof _: [Data32]) async -> Bool {
        // This would normally verify the Merkle proof
        // For now, we'll just return true
        true
    }

    // MARK: - Shard Distribution (CE 137)

    /// Distribute shards to validators
    /// - Parameters:
    ///   - shards: The shards to distribute
    ///   - erasureRoot: The erasure root of the data
    ///   - validators: The validators to distribute to
    /// - Returns: Success status of the distribution
    public func distributeShards(
        shards _: [Data4104],
        erasureRoot _: Data32,
        validators _: [ValidatorIndex]
    ) async throws -> Bool {
        // TODO: Implement shard distribution to validators
        // 1. Determine which shards go to which validators
        // 2. Send shards to validators over the network
        // 3. Track distribution status
        // 4. Return success status
        throw DataAvailabilityError.distributionError
    }

    // MARK: - Audit Shard Requests (CE 138)

    /// Request audit shards from validators
    /// - Parameters:
    ///   - workPackageHash: The hash of the work package
    ///   - indices: The indices of the shards to request
    ///   - validators: The validators to request from
    /// - Returns: The requested audit shards
    public func requestAuditShards(
        workPackageHash _: Data32,
        indices _: [UInt16],
        validators _: [ValidatorIndex]
    ) async throws -> [Data4104] {
        // TODO: Implement audit shard requests
        // 1. Determine which validators to request from
        // 2. Send requests to validators
        // 3. Collect responses
        // 4. Verify received shards
        // 5. Return valid shards
        throw DataAvailabilityError.retrievalError
    }

    /// Handle incoming audit shard requests
    /// - Parameters:
    ///   - workPackageHash: The hash of the work package
    ///   - indices: The indices of the requested shards
    ///   - requester: The validator requesting the shards
    /// - Returns: The requested audit shards
    public func handleAuditShardRequest(
        workPackageHash _: Data32,
        indices _: [UInt16],
        requester _: ValidatorIndex
    ) async throws -> [Data4104] {
        // TODO: Implement handling of audit shard requests
        // 1. Verify the requester is authorized
        // 2. Retrieve the requested shards from the audit store
        // 3. Return the shards to the requester
        throw DataAvailabilityError.retrievalError
    }

    // MARK: - Segment Shard Requests (CE 139/140)

    /// Request segment shards from validators
    /// - Parameters:
    ///   - segmentsRoot: The root of the segments
    ///   - indices: The indices of the shards to request
    ///   - validators: The validators to request from
    /// - Returns: The requested segment shards
    public func requestSegmentShards(
        segmentsRoot _: Data32,
        indices _: [UInt16],
        validators _: [ValidatorIndex]
    ) async throws -> [Data4104] {
        // TODO: Implement segment shard requests
        // 1. Determine which validators to request from
        // 2. Send requests to validators
        // 3. Collect responses
        // 4. Verify received shards
        // 5. Return valid shards
        throw DataAvailabilityError.retrievalError
    }

    /// Handle incoming segment shard requests
    /// - Parameters:
    ///   - segmentsRoot: The root of the segments
    ///   - indices: The indices of the requested shards
    ///   - requester: The validator requesting the shards
    /// - Returns: The requested segment shards
    public func handleSegmentShardRequest(
        segmentsRoot _: Data32,
        indices _: [UInt16],
        requester _: ValidatorIndex
    ) async throws -> [Data4104] {
        // TODO: Implement handling of segment shard requests
        // 1. Verify the requester is authorized
        // 2. Retrieve the requested shards from the import store
        // 3. Return the shards to the requester
        throw DataAvailabilityError.retrievalError
    }

    // MARK: - Assurance Distribution (CE 141)

    /// Distribute assurances to validators
    /// - Parameters:
    ///   - assurances: The assurances to distribute
    ///   - parentHash: The parent hash of the block
    ///   - validators: The validators to distribute to
    /// - Returns: Success status of the distribution
    public func distributeAssurances(
        assurances _: ExtrinsicAvailability.AssurancesList,
        parentHash _: Data32,
        validators _: [ValidatorIndex]
    ) async throws -> Bool {
        // TODO: Implement assurance distribution
        // 1. Verify the assurances are valid
        // 2. Distribute assurances to validators
        // 3. Track distribution status
        // 4. Return success status
        throw DataAvailabilityError.distributionError
    }

    /// Verify assurances from validators
    /// - Parameters:
    ///   - assurances: The assurances to verify
    ///   - parentHash: The parent hash of the block
    /// - Returns: The valid assurances
    public func verifyAssurances(
        assurances _: ExtrinsicAvailability.AssurancesList,
        parentHash _: Data32
    ) async throws -> ExtrinsicAvailability.AssurancesList {
        // TODO: Implement assurance verification
        // 1. Verify each assurance signature
        // 2. Verify the assurance is for the correct parent hash
        // 3. Return the valid assurances
        throw DataAvailabilityError.invalidErasureRoot
    }
}
