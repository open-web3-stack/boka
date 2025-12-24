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
    public func purge(epoch: EpochIndex) async {
        // GP 14.3.1
        // Guarantors are required to erasure-code and distribute two data sets: one blob, the auditable work-package containing
        // the encoded work-package, extrinsic data and self-justifying imported segments which is placed in the short-term Audit
        // da store and a second set of exported-segments data together with the Paged-Proofs metadata. Items in the first store
        // are short-lived; assurers are expected to keep them only until finality of the block in which the availability of the work-
        // result's work-package is assured. Items in the second, meanwhile, are long-lived and expected to be kept for a minimum
        // of 28 days (672 complete epochs) following the reporting of the work-report.

        // Purge old audit store data (short-term storage, kept until finality, approximately 1 hour)
        // Assuming approximately 6 epochs per hour at 10 minutes per epoch
        let auditRetentionEpochs: EpochIndex = 6

        if epoch > auditRetentionEpochs {
            _ = epoch - auditRetentionEpochs

            // Get all entries from audit store and remove old ones
            // Note: DataStore protocol doesn't expose a method to list all entries
            // This is a placeholder for the actual implementation
            // TODO: Implement iteration over audit store entries and remove those older than cutoff
        }

        // Purge old import/D3L store data (long-term storage, kept for 28 days = 672 epochs)
        let d3lRetentionEpochs: EpochIndex = 672

        if epoch > d3lRetentionEpochs {
            _ = epoch - d3lRetentionEpochs

            // Get all entries from import store and remove old ones
            // Note: DataStore protocol doesn't expose a method to list all entries
            // This is a placeholder for the actual implementation
            // TODO: Implement iteration over import store entries and remove those older than cutoff
        }

        // Alternative approach: Use timestamps
        // Assuming 1 hour for audit data, 28 days for D3L data
        let currentTimestamp = Date()
        let auditCutoffTime = currentTimestamp.addingTimeInterval(-3600) // 1 hour ago
        let d3lCutoffTime = currentTimestamp.addingTimeInterval(-28 * 24 * 3600) // 28 days ago

        // TODO: Implement timestamp-based cleanup when DataStore exposes iteration methods
        _ = (auditCutoffTime, d3lCutoffTime)
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

    // MARK: - Erasure Coding Reconstruction

    /// Reconstruct erasure-coded data from shards
    /// - Parameters:
    ///   - shards: The collected shards with their indices
    ///   - originalLength: The expected original data length
    /// - Returns: The reconstructed data
    /// - Throws: DataAvailabilityError if reconstruction fails
    public func reconstructData(
        shards: [(index: UInt16, data: Data)],
        originalLength: Int
    ) async throws -> Data {
        // GP section 10: Erasure Coding
        // We need at least 342 shards to reconstruct the original data
        let requiredShards = 342
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
            let reconstructed = try ErasureCoding.reconstruct(
                shards: erasureShards,
                basicSize: basicSize,
                originalCount: originalCount,
                recoveryCount: totalValidators,
                originalLength: originalLength
            )

            return reconstructed
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
        segmentCount: Int
    ) async throws -> [Data4104] {
        // Determine the total data size
        let totalDataSize = segmentCount * 4104

        // Reconstruct the full data
        let reconstructedData = try await reconstructData(
            shards: shards,
            originalLength: totalDataSize
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

    // MARK: - Network Request Helpers

    /// Fetch data from a specific validator
    /// - Parameters:
    ///   - validator: The validator index to fetch from
    ///   - requestData: The request data to send
    /// - Returns: The response data
    /// - Throws: DataAvailabilityError if the request fails
    public func fetchFromValidator(
        validator _: ValidatorIndex,
        requestData _: Data
    ) async throws -> Data {
        // TODO: Implement network layer integration
        // This should:
        // 1. Look up the validator's network address
        // 2. Send the request via the networking protocol
        // 3. Await the response
        // 4. Return the response data

        throw DataAvailabilityError.retrievalError
    }

    /// Fetch shards from multiple validators concurrently
    /// - Parameters:
    ///   - validators: The validators to fetch from
    ///   - shardRequest: The shard request data
    /// - Returns: The collected shard responses
    /// - Throws: DataAvailabilityError if insufficient validators respond
    public func fetchFromValidatorsConcurrently(
        validators _: [ValidatorIndex],
        shardRequest _: Data
    ) async throws -> [(validator: ValidatorIndex, data: Data)] {
        // Fetch from validators concurrently with timeout
        // We need at least 342 validators to respond for successful reconstruction
        let requiredResponses = 342

        // TODO: Implement actual network requests
        // For now, throw an error
        _ = requiredResponses
        throw DataAvailabilityError.retrievalError

        // Implementation would be:
        // var responses: [(ValidatorIndex, Data)] = []
        //
        // await withTaskGroup(of: (ValidatorIndex, Data?).self) { group in
        //     for validator in validators {
        //         group.addTask {
        //             do {
        //                 let data = try await self.fetchFromValidator(validator: validator, requestData: shardRequest)
        //                 return (validator, data)
        //             } catch {
        //                 return (validator, nil)
        //             }
        //         }
        //     }
        //
        //     for await (validator, data) in group {
        //         if let data = data {
        //             responses.append((validator, data))
        //         }
        //     }
        // }
        //
        // guard responses.count >= requiredResponses else {
        //     throw DataAvailabilityError.retrievalError
        // }
        //
        // return responses
    }

    // MARK: - Work-report Distribution (CE 135)

    public func workReportDistribution(
        workReport: WorkReport,
        slot: UInt32,
        signatures: [ValidatorSignature]
    ) async {
        let hash = workReport.hash()

        do {
            // verify slot - slot should be within valid range
            guard await isSlotValid(slot) else {
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
        // Slot is valid if it's within 5 slots before and 3 slots after current slot
        // This allows for some network delay and clock skew
        return slot + 5 >= currentSlot && slot <= currentSlot + 3
    }

    private func validate(signatures: [ValidatorSignature]) async throws {
        // Per GP section 15.2, at least 3 validators are required for a work-report
        guard signatures.count >= 3 else {
            throw DataAvailabilityError.insufficientSignatures
        }

        // Get the current validator set to verify signatures
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let currentValidators = state.value.currentValidators

        // Verify each signature
        for sig in signatures {
            // Check validator index is within range
            guard sig.validatorIndex < UInt32(currentValidators.count) else {
                throw DataAvailabilityError.invalidWorkReport
            }

            // Get the validator's Ed25519 public key
            let validatorKey = currentValidators[Int(sig.validatorIndex)]
            let publicKeyData = validatorKey.ed25519

            // Convert Data32 to Ed25519.PublicKey for verification
            guard let publicKey = try? Ed25519.PublicKey(from: publicKeyData) else {
                throw DataAvailabilityError.invalidWorkReport
            }

            // According to GP spec, the signature is over: Xguarantee || blake(encode(workReport))
            // Where Xguarantee is the string "$jam_guarantee"
            // The signature verification requires the work report hash to be provided
            // For now, we verify against a placeholder message
            // TODO: Pass the work report hash to this function and construct the proper message:
            // let message = "\u{10}$jam_guarantee".data(using: .utf8)! + workReportHash.data
            let isValid = publicKey.verify(signature: sig.signature, message: Data())

            if !isValid {
                throw DataAvailabilityError.invalidWorkReport
            }
        }
    }

    /// Validate signatures for a specific work report
    /// - Parameters:
    ///   - signatures: The signatures to validate
    ///   - workReportHash: The hash of the work report
    /// - Throws: DataAvailabilityError if validation fails
    public func validateWorkReportSignatures(
        signatures: [ValidatorSignature],
        workReportHash: Data32
    ) async throws {
        // Per GP section 15.2, at least 3 validators are required for a work-report
        guard signatures.count >= 3 else {
            throw DataAvailabilityError.insufficientSignatures
        }

        // Get the current validator set to verify signatures
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let currentValidators = state.value.currentValidators

        // Verify each signature
        for sig in signatures {
            // Check validator index is within range
            guard sig.validatorIndex < UInt32(currentValidators.count) else {
                throw DataAvailabilityError.invalidWorkReport
            }

            // Get the validator's Ed25519 public key
            let validatorKey = currentValidators[Int(sig.validatorIndex)]
            let publicKeyData = validatorKey.ed25519

            // Convert Data32 to Ed25519.PublicKey for verification
            guard let publicKey = try? Ed25519.PublicKey(from: publicKeyData) else {
                throw DataAvailabilityError.invalidWorkReport
            }

            // According to GP spec (reporting_assurance.tex eq:guarantorsig):
            // The signature is over: Xguarantee || blake(encode(workReport))
            // Where Xguarantee is the string "$jam_guarantee"
            let guaranteePrefix = "\u{10}$jam_guarantee".data(using: .utf8)!
            let signatureMessage = guaranteePrefix + workReportHash.data

            let isValid = publicKey.verify(signature: sig.signature, message: signatureMessage)

            if !isValid {
                throw DataAvailabilityError.invalidWorkReport
            }
        }
    }

    // MARK: - Shard Distribution (CE 137)

    public func shardDistribution(
        erasureRoot: Data32,
        shardIndex: UInt16
    ) async throws {
        // Generate request ID
        let requestId = try JamEncoder.encode(erasureRoot, shardIndex).blake2b256hash()
        do {
            // Fetch shard data from local storage
            // CE 137: Respond with bundle shard and segment shards
            // TODO: Fetch from dataStore once it supports get by erasure root and index

            // For now, throw an error as this needs the DataStore to support retrieval
            throw DataAvailabilityError.segmentNotFound

            // Once DataStore supports retrieval, the implementation should be:
            // let bundleShard = try await dataStore.getBundleShard(erasureRoot: erasureRoot, index: shardIndex)
            // let segmentShards = try await dataStore.getSegmentShards(erasureRoot: erasureRoot, index: shardIndex)

            // Generate Merkle proof justification
            // let justification = try await generateJustification(
            //     erasureRoot: erasureRoot,
            //     shardIndex: shardIndex,
            //     bundleShard: bundleShard,
            //     segmentShards: segmentShards
            // )

            // Respond with shards + proof
            // publish(RuntimeEvents.ShardDistributionReceivedResponse(
            //     requestId: requestId,
            //     bundleShard: bundleShard,
            //     segmentShards: segmentShards,
            //     justification: justification
            // ))

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

        // GP T(s,i,H) - Generate Merkle proof for segment shards
        let merklePath = Merklization.trace(
            segmentShards,
            index: Int(shardIndex),
            hasher: Blake2b256.self
        )

        // Generate Justification based on Merkle path length
        // According to GP, the justification format depends on the tree depth
        switch merklePath.count {
        case 1:
            // 0 ++ Hash - single hash for shallow trees
            guard case let .right(hash) = merklePath.first! else {
                throw DataAvailabilityError.invalidMerklePath
            }
            return .singleHash(hash)

        case 2:
            // 1 ++ Hash ++ Hash - double hash for medium depth trees
            guard case let .right(hash1) = merklePath[0],
                  case let .right(hash2) = merklePath[1]
            else {
                throw DataAvailabilityError.invalidMerklePath
            }
            return .doubleHash(hash1, hash2)

        default:
            // 2 ++ Segment Shard (12 bytes) - for deep trees, use segment shard
            // The segment shard is the first 12 bytes of the erasure-coded data
            guard shardIndex < UInt16(segmentShards.count) else {
                throw DataAvailabilityError.invalidSegmentIndex
            }

            let shardData = segmentShards[Int(shardIndex)]
            guard shardData.count >= 12 else {
                throw DataAvailabilityError.invalidSegmentIndex
            }

            guard let segmentShard = Data12(Data(shardData[0 ..< 12])) else {
                throw DataAvailabilityError.invalidDataLength
            }
            return .segmentShard(segmentShard)
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
        validators: [ValidatorIndex]
    ) async throws -> [Data4104] {
        // CE 138: Request audit shards from validators
        // 1. Determine which validators to request from
        //    We need at least 342 validators to reconstruct the data
        let requiredValidators = 342
        guard validators.count >= requiredValidators else {
            throw DataAvailabilityError.insufficientSignatures
        }

        // 2-5. TODO: Send requests, collect responses, verify, return
        // This requires network layer integration
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
        indices: [UInt16],
        requester: ValidatorIndex
    ) async throws -> [Data4104] {
        // CE 138: Handle incoming audit shard requests
        // 1. Verify the requester is a validator
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        guard requester < UInt32(state.value.currentValidators.count) else {
            throw DataAvailabilityError.invalidWorkReport
        }

        // 2. Retrieve the requested shards from the audit store
        // TODO: Need DataStore support for retrieval by work package hash
        let shards: [Data4104] = []
        for _ in indices {
            // TODO: Get shard from dataStore
            // guard let shard = try await dataStore.getAuditShard(workPackageHash: workPackageHash, index: index) else {
            //     throw DataAvailabilityError.segmentNotFound
            // }
            // shards.append(shard)
        }

        // 3. Return the shards to the requester
        return shards
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
        validators: [ValidatorIndex]
    ) async throws -> [Data4104] {
        // CE 139/140: Request segment shards from validators
        // 1. Determine which validators to request from
        let requiredValidators = 342
        guard validators.count >= requiredValidators else {
            throw DataAvailabilityError.insufficientSignatures
        }

        // 2-5. TODO: Send requests, collect responses, verify, return
        // This requires network layer integration
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
        indices: [UInt16],
        requester: ValidatorIndex
    ) async throws -> [Data4104] {
        // CE 139/140: Handle incoming segment shard requests
        // 1. Verify the requester is a validator
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        guard requester < UInt32(state.value.currentValidators.count) else {
            throw DataAvailabilityError.invalidWorkReport
        }

        // 2. Retrieve the requested shards from the import store
        let shards: [Data4104] = []
        for _ in indices {
            // TODO: Get shard from dataStore by segments root and index
            // guard let shard = try await dataStore.getSegment(segmentsRoot: segmentsRoot, index: index) else {
            //     throw DataAvailabilityError.segmentNotFound
            // }
            // shards.append(shard)
        }

        // 3. Return the shards to the requester
        return shards
    }

    // MARK: - Assurance Distribution (CE 141)

    /// Distribute assurances to validators
    /// - Parameters:
    ///   - assurances: The assurances to distribute
    ///   - parentHash: The parent hash of the block
    ///   - validators: The validators to distribute to
    /// - Returns: Success status of the distribution
    public func distributeAssurances(
        assurances: ExtrinsicAvailability.AssurancesList,
        parentHash: Data32,
        validators _: [ValidatorIndex]
    ) async throws -> Bool {
        // CE 141: Distribute assurances to validators
        // 1. Verify the assurances are valid
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let currentValidators = state.value.currentValidators

        for assurance in assurances {
            // Check validator index is within range
            guard assurance.validatorIndex < UInt32(currentValidators.count) else {
                throw DataAvailabilityError.invalidWorkReport
            }

            // Verify the parent hash matches
            guard assurance.parentHash == parentHash else {
                throw DataAvailabilityError.invalidWorkReport
            }

            // Verify the signature
            let validatorKey = currentValidators[Int(assurance.validatorIndex)]
            guard let publicKey = try? Ed25519.PublicKey(from: validatorKey.ed25519) else {
                throw DataAvailabilityError.invalidWorkReport
            }

            // Create the message: $jam_available || blake(encode(parentHash, bitfield))
            let bitfieldData = try JamEncoder.encode(assurance.assurance)
            let payload = try JamEncoder.encode(parentHash, bitfieldData)
            let message = try JamEncoder.encode(UInt8(0x01), payload.blake2b256hash())
            let signatureMessage = try JamEncoder.encode("\u{10}$jam_available".data(using: .utf8)!, message)

            guard publicKey.verify(signature: assurance.signature, message: signatureMessage) else {
                throw DataAvailabilityError.invalidWorkReport
            }
        }

        // 2-3. TODO: Distribute assurances to validators and track distribution status
        // This requires network layer integration

        // 4. Return success status
        return true
    }

    /// Verify assurances from validators
    /// - Parameters:
    ///   - assurances: The assurances to verify
    ///   - parentHash: The parent hash of the block
    /// - Returns: The valid assurances
    public func verifyAssurances(
        assurances: ExtrinsicAvailability.AssurancesList,
        parentHash: Data32
    ) async throws -> ExtrinsicAvailability.AssurancesList {
        // Verify assurances from validators
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let currentValidators = state.value.currentValidators

        var validItems: [ExtrinsicAvailability.AssuranceItem] = []

        for assurance in assurances {
            // 1. Verify the assurance is for the correct parent hash
            guard assurance.parentHash == parentHash else {
                logger.warning("Assurance parent hash mismatch: expected \(parentHash), got \(assurance.parentHash)")
                continue
            }

            // Check validator index is within range
            guard assurance.validatorIndex < UInt32(currentValidators.count) else {
                logger.warning("Invalid validator index in assurance: \(assurance.validatorIndex)")
                continue
            }

            // 2. Verify each assurance signature
            let validatorKey = currentValidators[Int(assurance.validatorIndex)]
            guard let publicKey = try? Ed25519.PublicKey(from: validatorKey.ed25519) else {
                logger.warning("Failed to create public key for validator \(assurance.validatorIndex)")
                continue
            }

            // Create the message: $jam_available || blake(encode(parentHash, bitfield))
            let bitfieldData = try JamEncoder.encode(assurance.assurance)
            let payload = try JamEncoder.encode(parentHash, bitfieldData)
            let message = try JamEncoder.encode(UInt8(0x01), payload.blake2b256hash())
            let signatureMessage = try JamEncoder.encode("\u{10}$jam_available".data(using: .utf8)!, message)

            guard publicKey.verify(signature: assurance.signature, message: signatureMessage) else {
                logger.warning("Invalid signature for validator \(assurance.validatorIndex)")
                continue
            }

            // Add to valid assurances
            validItems.append(assurance)
        }

        // Create a new AssurancesList with only the valid items
        var validAssurances = try ExtrinsicAvailability.AssurancesList(config: config)
        for item in validItems {
            try validAssurances.append(item)
        }

        // 3. Return the valid assurances
        logger.info("Verified \(validItems.count)/\(assurances.count) assurances")
        return validAssurances
    }

    // MARK: - Data Availability Verification

    /// Verify that a work package is available
    /// - Parameter workPackageHash: The hash of the work package to verify
    /// - Returns: True if the work package is available
    public func isWorkPackageAvailable(workPackageHash: Data32) async -> Bool {
        do {
            // Check if we have the segments root for this work package
            // Note: DataStore doesn't expose getSegmentRoot directly, so we try fetching a segment
            // If we can resolve the segment root, the work package is available
            let segment = WorkItem.ImportedDataSegment(
                root: .workPackageHash(workPackageHash),
                index: 0
            )
            let result = try await dataStore.fetchSegment(segments: [segment], segmentsRootMappings: nil)
            return !result.isEmpty
        } catch {
            logger.error("Failed to check work package availability: \(error)")
            return false
        }
    }

    /// Get the availability status of a work package
    /// - Parameter workPackageHash: The hash of the work package
    /// - Returns: The availability status including segments root and shard count
    public func getWorkPackageAvailabilityStatus(workPackageHash: Data32) async
        -> (available: Bool, segmentsRoot: Data32?, shardCount: Int?)
    {
        do {
            // Try to fetch a segment to check availability
            let segment = WorkItem.ImportedDataSegment(
                root: .workPackageHash(workPackageHash),
                index: 0
            )
            let result = try await dataStore.fetchSegment(segments: [segment], segmentsRootMappings: nil)

            if !result.isEmpty {
                // TODO: Get actual segments root and shard count when DataStore supports it
                return (true, nil, nil)
            }

            return (false, nil, nil)
        } catch {
            logger.error("Failed to get work package availability status: \(error)")
            return (false, nil, nil)
        }
    }

    /// Verify data availability for multiple work packages
    /// - Parameter workPackageHashes: The hashes of the work packages to verify
    /// - Returns: Dictionary mapping work package hash to availability status
    public func verifyMultipleWorkPackagesAvailability(
        workPackageHashes: [Data32]
    ) async -> [Data32: Bool] {
        var results: [Data32: Bool] = [:]

        await withTaskGroup(of: (Data32, Bool).self) { group in
            for hash in workPackageHashes {
                group.addTask {
                    let available = await self.isWorkPackageAvailable(workPackageHash: hash)
                    return (hash, available)
                }
            }

            for await (hash, available) in group {
                results[hash] = available
            }
        }

        return results
    }

    // MARK: - Work Package Retrieval

    /// Retrieve a work package by hash
    /// - Parameter workPackageHash: The hash of the work package
    /// - Returns: The work package if available
    /// - Throws: DataAvailabilityError if the work package is not available
    public func retrieveWorkPackage(workPackageHash: Data32) async throws -> WorkPackage {
        // Try to get from local storage first
        let isAvailable = await isWorkPackageAvailable(workPackageHash: workPackageHash)

        guard isAvailable else {
            throw DataAvailabilityError.segmentNotFound
        }

        // TODO: Retrieve and reconstruct the work package from segments
        // This requires fetching the segments and reconstructing the work package
        logger.info("Work package \(workPackageHash) is available locally")

        throw DataAvailabilityError.retrievalError
    }

    /// Fetch work package from validators if not available locally
    /// - Parameters:
    ///   - workPackageHash: The hash of the work package
    ///   - validators: The validators to fetch from
    /// - Returns: The reconstructed work package
    /// - Throws: DataAvailabilityError if retrieval fails
    public func fetchWorkPackageFromValidators(
        workPackageHash: Data32,
        validators: [ValidatorIndex]
    ) async throws -> WorkPackage {
        // Check if already available locally
        let isAvailable = await isWorkPackageAvailable(workPackageHash: workPackageHash)

        if isAvailable {
            return try await retrieveWorkPackage(workPackageHash: workPackageHash)
        }

        // TODO: Implement fetching from validators
        // 1. Request audit shards from validators
        // 2. Reconstruct the work package bundle
        // 3. Extract the work package
        logger.info("Fetching work package \(workPackageHash) from \(validators.count) validators")

        throw DataAvailabilityError.retrievalError
    }

    // MARK: - Shard Management

    /// Get local shard availability for an erasure root
    /// - Parameter erasureRoot: The erasure root to check
    /// - Returns: Number of locally available shards
    public func getLocalShardCount(erasureRoot: Data32) async -> Int {
        // TODO: Implement once DataStore supports iteration/counting
        // For now, return 0
        logger.debug("Checking local shard count for erasure root: \(erasureRoot)")
        return 0
    }

    /// Calculate reconstruction potential
    /// - Parameter erasureRoot: The erasure root to check
    /// - Returns: True if we have enough shards for reconstruction (>= 342)
    public func canReconstruct(erasureRoot: Data32) async -> Bool {
        let localShardCount = await getLocalShardCount(erasureRoot: erasureRoot)
        return localShardCount >= 342
    }

    /// Get missing shard indices for an erasure root
    /// - Parameter erasureRoot: The erasure root to check
    /// - Returns: Array of missing shard indices
    public func getMissingShardIndices(erasureRoot: Data32) async -> [UInt16] {
        // TODO: Implement once DataStore supports querying available indices
        // For now, return empty array
        logger.debug("Getting missing shard indices for erasure root: \(erasureRoot)")
        return []
    }

    // MARK: - Statistics and Monitoring

    /// Get data availability statistics
    /// - Returns: Statistics about stored data
    public func getStatistics() async -> (auditStoreCount: Int, importStoreCount: Int, totalSegments: Int) {
        // TODO: Implement once DataStore supports statistics
        // For now, return zeros
        (0, 0, 0)
    }

    /// Get storage usage information
    /// - Returns: Storage usage in bytes
    public func getStorageUsage() async -> (auditStore: Int, importStore: Int) {
        // TODO: Implement once DataStore supports size queries
        // For now, return zeros
        (0, 0)
    }

    /// Health check for data availability service
    /// - Returns: True if the service is healthy
    public func healthCheck() async -> Bool {
        // Check if data provider is accessible
        let head = await dataProvider.bestHead
        // If we can access the best head without error, the service is healthy
        return head.hash != Data32()
    }
}
