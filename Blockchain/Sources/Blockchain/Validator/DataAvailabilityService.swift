import Codec
import Foundation
import Synchronization
import TracingUtils
import Utils

public enum DataAvailabilityError: Error {
    case storeError
    case retrievalError
    case erasureCodingError
    case distributionError
    case segmentNotFound
    case segmentsRootMappingNotFound
    case invalidSegmentIndex
    case invalidErasureRoot
    case invalidSegmentsRoot
    case invalidDataLength
    case pagedProofsGenerationError
    case invalidWorkReportSlot
    case invalidWorkReport
    case insufficientSignatures
    case invalidMerklePath
    case emptySegmentShards
    case invalidJustificationFormat
}

public final class DataAvailabilityService: ServiceBase2, @unchecked Sendable, OnSyncCompleted {
    private let dataProvider: BlockchainDataProvider
    private let dataStore: DataStore

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

    public func onSyncCompleted() async {
        await subscribe(RuntimeEvents.WorkReportReceived.self, id: "DataAvailabilityService.WorkReportReceived") { [weak self] event in
            await self?.handleWorkReportReceived(event)
        }
        await subscribe(RuntimeEvents.ShardDistributionReceived.self,
                        id: "DataAvailabilityService.ShardDistributionReceived")
        { [weak self] event in
            await self?.handleShardDistributionReceived(event)
        }
    }

    public func handleWorkReportReceived(_ event: RuntimeEvents.WorkReportReceived) async {
        await workReportDistribution(workReport: event.workReport, slot: event.slot, signatures: event.signatures)
    }

    public func handleShardDistributionReceived(_ event: RuntimeEvents.ShardDistributionReceived) async {
        try? await shardDistribution(erasureRoot: event.erasureRoot, shardIndex: event.shardIndex)
    }

    /// Purge old data from the data availability stores
    /// - Parameter epoch: The current epoch index
    public func purge(epoch _: EpochIndex) async {
        // GP 14.3.1
        // Guarantors are required to erasure-code and distribute two data sets: one blob, the auditable work-package containing
        // the encoded work-package, extrinsic data and self-justifying imported segments which is placed in the short-term Audit
        // da store and a second set of exported-segments data together with the Paged-Proofs metadata. Items in the first store
        // are short-lived; assurers are expected to keep them only until finality of the block in which the availability of the work-
        // result's work-package is assured. Items in the second, meanwhile, are long-lived and expected to be kept for a minimum
        // of 28 days (672 complete epochs) following the reporting of the work-report.
    }

    /// Fetch segments from import store
    /// - Parameters:
    ///   - segments: The segment specifications to retrieve
    ///   - segmentsRootMappings: Optional mappings from work package hash to segments root
    /// - Returns: The retrieved segments
    public func fetchSegment(
        segments: [WorkItem.ImportedDataSegment],
        segmentsRootMappings: SegmentsRootMappings? = nil
    ) async throws -> [Data4104] {
        // Delegate segment fetching to the data store.
        // The dataStore handles resolving segment roots and retrieving from the appropriate underlying storage.
        try await dataStore.fetchSegment(segments: segments, segmentsRootMappings: segmentsRootMappings)
    }

    /// Export segments to import store
    /// - Parameters:
    ///   - data: The segments to export
    ///   - erasureRoot: The erasure root to associate with the segments
    /// - Returns: The segments root
    public func exportSegments(data: [Data4104], erasureRoot: Data32) async throws -> Data32 {
        let segmentRoot = Merklization.constantDepthMerklize(data.map(\.data))

        let currentTimestamp = Date()
        try await dataStore.setTimestamp(erasureRoot: erasureRoot, timestamp: currentTimestamp)

        let pagedProofsMetadata = try generatePagedProofsMetadata(data: data, segmentRoot: segmentRoot)
        try await dataStore.setPagedProofsMetadata(erasureRoot: erasureRoot, metadata: pagedProofsMetadata)

        for (index, segmentData) in data.enumerated() {
            try await dataStore.set(
                data: segmentData,
                erasureRoot: erasureRoot,
                index: UInt16(index)
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

    /// Export a work package bundle to audit store
    /// - Parameter bundle: The bundle to export
    /// - Returns: The erasure root and length of the bundle
    public func exportWorkpackageBundle(bundle: WorkPackageBundle) async throws -> (erasureRoot: Data32, length: DataLength) {
        // Serialize the bundle
        let serializedData = try JamEncoder.encode(bundle)
        let dataLength = DataLength(UInt32(serializedData.count))

        // Calculate the erasure root
        // Work-package bundle shard hash
        let bundleShards = try ErasureCoding.chunk(
            data: serializedData,
            basicSize: config.value.erasureCodedPieceSize,
            recoveryCount: config.value.totalNumberOfValidators
        )
        // Chunk the bundle into segments
        let segmentCount = serializedData.count / 4104
        var segments = [Data4104]()
        for i in 0 ..< segmentCount {
            let start = i * 4104
            let end = min(start + 4104, serializedData.count)
            var segment = Data(count: 4104)
            segment.withUnsafeMutableBytes { destPtr in
                serializedData.withUnsafeBytes { sourcePtr in
                    destPtr.baseAddress!.copyMemory(from: sourcePtr.baseAddress! + start, byteCount: end - start)
                }
            }
            segments.append(Data4104(segment)!)
        }

        // Calculate the segments root
        let segmentsRoot = Merklization.constantDepthMerklize(segments.map(\.data))

        var nodes = [Data]()
        // workpackage bundle shard hash + segment shard root
        for i in 0 ..< bundleShards.count {
            let shardHash = bundleShards[i].blake2b256hash()
            try nodes.append(JamEncoder.encode(shardHash) + JamEncoder.encode(segmentsRoot))
        }

        // ErasureRoot
        let erasureRoot = Merklization.binaryMerklize(nodes)

        // Extract the work package hash from the bundle
        let workPackageHash = bundle.workPackage.hash()

        // Store the serialized bundle in the audit store (short-term storage)
        // Store the segment in the data store
        for (i, segment) in segments.enumerated() {
            try await dataStore.set(data: segment, erasureRoot: erasureRoot, index: UInt16(i))
        }

        // Map the work package hash to the segments root
        try await dataStore.setSegmentRoot(segmentRoot: segmentsRoot, forWorkPackageHash: workPackageHash)

        // Set the timestamp for retention tracking
        // As per GP 14.3.1, items in the audit store are kept until finality (approx. 1 hour)
        let currentTimestamp = Date()
        try await dataStore.setTimestamp(erasureRoot: erasureRoot, timestamp: currentTimestamp)

        // 8. Return the erasure root and length
        return (erasureRoot: erasureRoot, length: dataLength)
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

    // MARK: - Work-report Distribution (CE 135)

    public func workReportDistribution(
        workReport: WorkReport,
        slot: UInt32,
        signatures: [ValidatorSignature]
    ) async {
        let hash = workReport.hash()

        do {
            // verify slot
            if await isSlotValid(slot) {
                throw DataAvailabilityError.invalidWorkReportSlot
            }
            // verify signatures
            try await validate(signatures: signatures)

            // store guaranteedWorkReport
            let report = GuaranteedWorkReport(
                workReport: workReport,
                slot: slot,
                signatures: signatures
            )
            try await dataProvider.add(guaranteedWorkReport: GuaranteedWorkReportRef(report))
            // response success result
            publish(RuntimeEvents.WorkReportReceivedResponse(workReportHash: hash))
        } catch {
            publish(RuntimeEvents.WorkReportReceivedResponse(workReportHash: hash, error: error))
        }
    }

    private func isSlotValid(_ slot: UInt32) async -> Bool {
        let currentSlot = await dataProvider.bestHead.timeslot
        return slot + 5 >= currentSlot && slot <= currentSlot + 3
    }

    private func validate(signatures: [ValidatorSignature]) async throws {
        guard signatures.count >= 3 else {
            throw DataAvailabilityError.insufficientSignatures
        }
        // TODO: more validates
    }

    // MARK: - Shard Distribution (CE 137)

    public func shardDistribution(
        erasureRoot: Data32,
        shardIndex: UInt16
    ) async throws {
        // Generate request ID
        let requestId = try JamEncoder.encode(erasureRoot, shardIndex).blake2b256hash()
        do {
            // TODO: Fetch shard data from local storage
            let (bundleShard, segmentShards) = (Data(), [Data()])

            // Generate Merkle proof justification
            let justification = try await generateJustification(
                erasureRoot: erasureRoot,
                shardIndex: shardIndex,
                bundleShard: bundleShard,
                segmentShards: segmentShards
            )

            // Respond with shards + proof
            publish(RuntimeEvents.ShardDistributionReceivedResponse(
                requestId: requestId,
                bundleShard: bundleShard,
                segmentShards: segmentShards,
                justification: justification
            ))

        } catch {
            publish(RuntimeEvents.ShardDistributionReceivedResponse(
                requestId: requestId,
                error: error
            ))
        }
    }

    private func generateJustification(
        erasureRoot _: Data32,
        shardIndex: UInt16,
        bundleShard _: Data,
        segmentShards: [Data]
    ) async throws -> Justification {
        guard !segmentShards.isEmpty else {
            throw DataAvailabilityError.emptySegmentShards
        }

        // GP T(s,i,H)
        let merklePath = Merklization.trace(
            segmentShards,
            index: Int(shardIndex),
            hasher: Blake2b256.self
        )

        // TODO: Got Justification
        switch merklePath.count {
        case 1:
            // 0 ++ Hash
            guard case let .right(hash) = merklePath.first! else {
                throw DataAvailabilityError.invalidMerklePath
            }
            return .singleHash(hash)

        case 2:
            // 1 ++ Hash ++ Hash
            guard case let .right(hash1) = merklePath[0],
                  case let .right(hash2) = merklePath[1]
            else {
                throw DataAvailabilityError.invalidMerklePath
            }
            return .doubleHash(hash1, hash2)

        default:
            // TODO: 2 ++ Segment Shard (12 bytes)
            return .segmentShard(Data12())
        }
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
