import Codec
import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "WorkReportProcessor")

/// Processor for work report erasure coding and reconstruction
///
/// Handles exporting segments/bundles with erasure coding,
/// and reconstructing data from shards
public actor WorkReportProcessor {
    private let dataStore: DataStore
    private let erasureCodingDataStore: ErasureCodingDataStore?
    private let erasureCodingService: ErasureCodingService
    private let config: ProtocolConfigRef

    public init(
        dataStore: DataStore,
        erasureCodingDataStore: ErasureCodingDataStore?,
        config: ProtocolConfigRef,
    ) {
        self.dataStore = dataStore
        self.erasureCodingDataStore = erasureCodingDataStore
        self.config = config
        erasureCodingService = ErasureCodingService(config: config)
    }

    // MARK: - Segment Operations

    /// Fetch segments from data store
    public func fetchSegment(
        segments: [WorkItem.ImportedDataSegment],
        segmentsRootMappings: SegmentsRootMappings? = nil,
    ) async throws -> [Data4104] {
        // Delegate segment fetching to the data store.
        // The dataStore handles resolving segment roots and retrieving from the appropriate underlying storage.
        try await dataStore.fetchSegment(segments: segments, segmentsRootMappings: segmentsRootMappings)
    }

    /// Export segments to import store with erasure coding
    /// - Parameters:
    ///   - data: The segments to export
    ///   - erasureRoot: The erasure root to associate with the segments
    /// - Returns: The segments root
    public func exportSegments(data: [Data4104], erasureRoot: Data32) async throws -> Data32 {
        // Use ErasureCodingDataStore if available for automatic erasure coding
        if let ecStore = erasureCodingDataStore {
            // For D³L store, we need to track work package hash
            // Use erasureRoot as temporary workPackageHash placeholder
            let workPackageHash = erasureRoot

            let segmentRoot = Merklization.constantDepthMerklize(data.map(\.data))

            // Store using ErasureCodingDataStore
            let storedErasureRoot = try await ecStore.storeExportedSegments(
                segments: data,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentRoot,
            )

            logger.info("Stored exported segments: erasureRoot=\(storedErasureRoot.toHexString()), count=\(data.count)")

            return segmentRoot
        }

        // Fallback to legacy implementation
        let segmentRoot = Merklization.constantDepthMerklize(data.map(\.data))

        let currentTimestamp = Date()
        try await dataStore.setTimestamp(erasureRoot: erasureRoot, timestamp: currentTimestamp)

        let pagedProofsMetadata = try generatePagedProofsMetadata(data: data, segmentRoot: segmentRoot)
        try await dataStore.setPagedProofsMetadata(erasureRoot: erasureRoot, metadata: pagedProofsMetadata)

        for (index, segmentData) in data.enumerated() {
            try await dataStore.set(
                data: segmentData,
                erasureRoot: erasureRoot,
                index: UInt16(index),
            )
        }

        return segmentRoot
    }

    /// Generate Paged-Proofs metadata for a set of segments
    /// - Parameters:
    ///   - data: The segments data
    ///   - segmentRoot: The segments root
    /// - Returns: The Paged-Proofs metadata
    /// - Throws: DataAvailabilityError if metadata generation fails
    private func generatePagedProofsMetadata(data: [Data4104], segmentRoot: Data32) throws -> Data {
        // TODO: replace this with real implementation

        // Use JamEncoder to properly encode the metadata
        let segmentCount = UInt32(data.count)
        var segmentHashes: [Data32] = []

        // Calculate segment hashes
        for segment in data {
            segmentHashes.append(segment.data.blake2b256hash())
        }

        // Encode the metadata using JamEncoder
        return try JamEncoder.encode(segmentCount, segmentRoot, segmentHashes)
    }

    // MARK: - Audit Bundle Operations

    /// Export a work package bundle to audit store with erasure coding
    /// - Parameter bundle: The bundle to export
    /// - Returns: The erasure root and length of the bundle
    public func exportWorkpackageBundle(bundle: WorkPackageBundle) async throws -> (erasureRoot: Data32, length: DataLength) {
        // Serialize the bundle
        let serializedData = try JamEncoder.encode(bundle)
        let dataLength = DataLength(UInt32(serializedData.count))

        // Extract the work package hash from the bundle
        let workPackageHash = bundle.workPackage.hash()

        // Use ErasureCodingDataStore if available for automatic erasure coding
        if let ecStore = erasureCodingDataStore {
            // Calculate segments root from bundle for validation
            let segmentCount = (serializedData.count + 4103) / 4104
            var segments = [Data4104]()
            for i in 0 ..< segmentCount {
                let start = i * 4104
                let end = min(start + 4104, serializedData.count)

                // Safely extract segment data using subdata
                var segmentData = serializedData.subdata(in: start ..< end)

                // Pad to 4104 bytes if necessary
                if segmentData.count < 4104 {
                    segmentData.append(Data(count: 4104 - segmentData.count))
                }

                if let seg = Data4104(segmentData) {
                    segments.append(seg)
                }
            }

            let segmentsRoot = Merklization.constantDepthMerklize(segments.map(\.data))

            // Store using ErasureCodingDataStore
            let erasureRoot = try await ecStore.storeAuditBundle(
                bundle: serializedData,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot,
            )

            logger.info("Stored audit bundle: erasureRoot=\(erasureRoot.toHexString()), length=\(serializedData.count)")

            return (erasureRoot, dataLength)
        }

        // Fallback to legacy DataStore (not implemented)
        logger.error("Audit bundle export requires ErasureCodingDataStore")
        throw DataAvailabilityError.storeError
    }

    /// Retrieve an audit bundle by erasure root
    /// - Parameter erasureRoot: The erasure root identifying the bundle
    /// - Returns: The audit bundle data, or nil if not found
    public func retrieveAuditBundle(erasureRoot: Data32) async throws -> Data? {
        // Use ErasureCodingDataStore if available
        if let ecStore = erasureCodingDataStore {
            return try await ecStore.getAuditBundle(erasureRoot: erasureRoot)
        }

        // Fallback: not supported by legacy DataStore
        logger.warning("Audit bundle retrieval requires ErasureCodingDataStore")
        return nil
    }

    // MARK: - Verification

    /// Verify that a segment belongs to an erasure root
    /// - Parameters:
    ///   - segment: The segment to verify
    ///   - index: The index of the segment
    ///   - erasureRoot: The erasure root to verify against
    ///   - proof: The Merkle proof for the segment
    /// - Returns: True if the segment is valid
    public func verifySegment(segment: Data4104, index: UInt16, erasureRoot: Data32, proof: [Data32]) async -> Bool {
        // Verify the Merkle proof for the segment
        // The proof should demonstrate that the segment's hash is included in the erasure root

        // Calculate the hash of the segment
        let segmentHash = segment.data.blake2b256hash()

        // Start with the segment hash as the current value
        var currentValue = segmentHash

        // Traverse the Merkle proof
        for (i, proofElement) in proof.enumerated() {
            // Determine if we're on the left or right side of the tree at this level
            let bitSet = (Int(index) >> i) & 1

            // Combine current value with proof element based on position
            if bitSet == 0 {
                // Current value is on the left
                let combined = currentValue.data + proofElement.data
                currentValue = combined.blake2b256hash()
            } else {
                // Current value is on the right
                let combined = proofElement.data + currentValue.data
                currentValue = combined.blake2b256hash()
            }
        }

        // The final computed hash should match the erasure root
        return currentValue == erasureRoot
    }

    // MARK: - Reconstruction

    /// Reconstruct erasure-coded data from shards
    /// - Parameters:
    ///   - shards: The collected shards with their indices
    ///   - originalLength: The expected original data length
    /// - Returns: The reconstructed data
    /// - Throws: DataAvailabilityError if reconstruction fails
    public func reconstructData(
        shards: [(index: UInt16, data: Data)],
        originalLength: Int,
    ) async throws -> Data {
        // GP section 10: Erasure Coding
        // We need at least minimumValidatorResponses shards to reconstruct the original data
        let requiredShards = DataAvailabilityConstants.minimumValidatorResponses
        guard shards.count >= requiredShards else {
            throw DataAvailabilityError.retrievalError
        }

        // Convert to ErasureCoding.Shard format
        let erasureShards = shards.map { shard in
            ErasureCoding.Shard(data: shard.data, index: UInt32(shard.index))
        }

        // Calculate parameters for reconstruction
        let basicSize = config.value.erasureCodedPieceSize
        let totalValidators = config.value.totalNumberOfValidators

        // Determine original count based on data size
        // For erasure coding, original count is approximately 1/3 of recovery count
        let originalCount = (totalValidators + 2) / 3

        do {
            // Use ErasureCoding.reconstruct to recover the original data
            return try ErasureCoding.reconstruct(
                shards: erasureShards,
                basicSize: basicSize,
                originalCount: originalCount,
                recoveryCount: totalValidators,
                originalLength: originalLength,
            )
        } catch {
            logger.error("Failed to reconstruct data from shards: \(error)")
            throw DataAvailabilityError.erasureCodingError
        }
    }

    /// Reconstruct segments from erasure-coded shards
    /// - Parameters:
    ///   - shards: The collected shards with their indices
    ///   - segmentCount: The expected number of segments
    /// - Returns: The reconstructed segments
    /// - Throws: DataAvailabilityError if reconstruction fails
    public func reconstructSegments(
        shards: [(index: UInt16, data: Data)],
        segmentCount: Int,
    ) async throws -> [Data4104] {
        // Determine the total data size
        let totalDataSize = segmentCount * 4104

        // Reconstruct the full data
        let reconstructedData = try await reconstructData(
            shards: shards,
            originalLength: totalDataSize,
        )

        // Split into segments
        var segments: [Data4104] = []
        for i in 0 ..< segmentCount {
            let start = i * 4104
            let end = min(start + 4104, reconstructedData.count)
            let segmentData = Data(reconstructedData[start ..< end])

            // Pad if necessary
            var paddedSegment = segmentData
            if paddedSegment.count < 4104 {
                paddedSegment.append(Data(count: 4104 - paddedSegment.count))
            }

            guard let segment = Data4104(paddedSegment) else {
                throw DataAvailabilityError.invalidDataLength
            }
            segments.append(segment)
        }

        return segments
    }

    // MARK: - Work Package Retrieval

    /// Retrieve a work package by hash
    /// - Parameter workPackageHash: The hash of the work package
    /// - Returns: The work package if available
    /// - Throws: DataAvailabilityError if the work package is not available
    public func retrieveWorkPackage(workPackageHash: Data32) async throws -> WorkPackage {
        // Try to get from local storage first
        let segment = WorkItem.ImportedDataSegment(
            root: .workPackageHash(workPackageHash),
            index: 0,
        )

        do {
            let segments = try await dataStore.fetchSegment(segments: [segment], segmentsRootMappings: nil)

            if !segments.isEmpty {
                let segmentData = segments[0].data
                return try JamDecoder.decode(WorkPackage.self, from: segmentData)
            }
        } catch {
            logger.debug("Work package not in local storage: \(error)")
        }

        throw DataAvailabilityError.segmentNotFound
    }

    /// Fetch work package from validators with network fallback
    public func fetchWorkPackageFromValidators(workPackageHash _: Data32) async throws -> WorkPackage {
        // TODO: Implement network fallback when ErasureCodingDataStore doesn't have it locally
        throw DataAvailabilityError.segmentNotFound
    }

    /// Batch reconstruction with network fallback
    public func batchReconstructWithFallback(
        erasureRoots: [Data32],
        originalLengths: [Data32: Int],
    ) async throws -> [Data32: Data] {
        guard let ecStore = erasureCodingDataStore else {
            throw DataAvailabilityError.segmentNotFound
        }

        return try await ecStore.batchReconstruct(
            erasureRoots: erasureRoots,
            originalLengths: originalLengths,
            validators: nil,
            coreIndex: 0,
            totalValidators: 1023,
        )
    }

    /// Fetch segments with network fallback
    public func fetchSegmentsWithFallback(
        erasureRoot: Data32,
        indices: [Int],
        validators: [UInt16: NetAddr]? = nil,
    ) async throws -> [Data4104] {
        guard let ecStore = erasureCodingDataStore else {
            throw DataAvailabilityError.segmentNotFound
        }

        return try await ecStore.getSegmentsWithNetworkFallback(
            erasureRoot: erasureRoot,
            indices: indices,
            validators: validators,
        )
    }
}
