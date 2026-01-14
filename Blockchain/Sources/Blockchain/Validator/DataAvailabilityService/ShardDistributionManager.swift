import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "ShardDistributionManager")

// GP spec constants from definitions.tex
private let cEcRecoveryCount = 1023 /// Recovery shard count

/// Manager for shard distribution and CE protocol message handlers
///
/// Handles work report distribution (CE 135), shard distribution (CE 137),
/// audit shard requests (CE 138), and segment shard requests (CE 139/140)
public actor ShardDistributionManager {
    private let dataProvider: BlockchainDataProvider
    private let dataStore: DataStore
    private let erasureCodingDataStore: ErasureCodingDataStore?
    private let erasureCodingService: ErasureCodingService

    public init(
        dataProvider: BlockchainDataProvider,
        dataStore: DataStore,
        erasureCodingDataStore: ErasureCodingDataStore?,
        config: ProtocolConfigRef
    ) {
        self.dataProvider = dataProvider
        self.dataStore = dataStore
        self.erasureCodingDataStore = erasureCodingDataStore
        erasureCodingService = ErasureCodingService(config: config)
    }

    // MARK: - Work Report Distribution (CE 135)

    public func workReportDistribution(
        workReport: WorkReport,
        slot: UInt32,
        signatures: [ValidatorSignature]
    ) async throws {
        let hash = workReport.hash()

        // verify slot - slot should be within valid range
        guard await isSlotValid(slot) else {
            throw DataAvailabilityError.invalidWorkReportSlot
        }
        // verify signatures
        try await validate(signatures: signatures, workReportHash: hash)

        // store guaranteedWorkReport
        let report = GuaranteedWorkReport(
            workReport: workReport,
            slot: slot,
            signatures: signatures
        )
        try await dataProvider.add(guaranteedWorkReport: GuaranteedWorkReportRef(report))
    }

    private func isSlotValid(_ slot: UInt32) async -> Bool {
        let currentSlot = await dataProvider.bestHead.timeslot
        // Slot is valid if it's within 5 slots before and 3 slots after current slot
        // This allows for some network delay and clock skew
        return slot + 5 >= currentSlot && slot <= currentSlot + 3
    }

    private func validate(signatures: [ValidatorSignature], workReportHash: Data32) async throws {
        // Per GP section 15.2, at least 3 validators are required for a work-report
        guard signatures.count >= 3 else {
            throw DataAvailabilityError.insufficientSignatures
        }

        // Get the current validator set to verify signatures
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let currentValidators = state.value.currentValidators

        // According to GP spec (reporting_assurance.tex eq:guarantorsig):
        // The signature is over: Xguarantee || blake(encode(workReport))
        // Where Xguarantee is the string "$jam_guarantee" (14 bytes) with a length prefix byte
        let guaranteePrefix = Data("\u{0E}$jam_guarantee".utf8)
        let signatureMessage = guaranteePrefix + workReportHash.data

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

            // Verify the signature over the constructed message
            let isValid = publicKey.verify(signature: sig.signature, message: signatureMessage)

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
            // Where Xguarantee is the string "$jam_guarantee" (14 bytes)
            let guaranteePrefix = Data("\u{0E}$jam_guarantee".utf8)
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
    ) async throws -> (bundleShard: Data, segmentShards: [Data], justification: AvailabilityJustification) {
        // CE 137: Respond with bundle shard and segment shards with justification

        // Use ErasureCodingDataStore if available
        guard let ecStore = erasureCodingDataStore else {
            throw DataAvailabilityError.segmentNotFound
        }

        // Check if we have this shard
        let hasShard = try await ecStore.hasShard(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )

        guard hasShard else {
            throw DataAvailabilityError.segmentNotFound
        }

        // Get shard data
        guard let shardData = try await ecStore.getShard(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        ) else {
            throw DataAvailabilityError.retrievalError
        }

        // Get metadata - we need both audit and D³L entries
        guard try await ecStore.getAuditEntry(erasureRoot: erasureRoot) != nil else {
            throw DataAvailabilityError.invalidErasureRoot
        }

        guard let d3lMetadata = try await ecStore.getD3LEntry(erasureRoot: erasureRoot) else {
            throw DataAvailabilityError.segmentsRootMappingNotFound
        }

        // Extract bundle shard (first 684 bytes)
        let bundleShardSize = 684
        guard shardData.count >= bundleShardSize else {
            throw DataAvailabilityError.invalidDataLength
        }

        let bundleShard = Data(shardData[0 ..< bundleShardSize])

        // Extract segment shards
        let segmentCount = Int(d3lMetadata.segmentCount)
        let segmentShardSize = (shardData.count - bundleShardSize) / segmentCount
        var segmentShards: [Data] = []

        for i in 0 ..< segmentCount {
            let startOffset = bundleShardSize + (i * segmentShardSize)
            let end = min(startOffset + segmentShardSize, shardData.count)
            let segmentShard = Data(shardData[startOffset ..< end])
            segmentShards.append(segmentShard)
        }

        // Generate justification T(s, i, H) using ErasureCodingService
        // Get all shard hashes for justification generation using batch operation
        let allShardIndices = Array(0 ..< UInt16(cEcRecoveryCount))
        let allShards = try await ecStore.getShards(
            erasureRoot: erasureRoot,
            shardIndices: allShardIndices
        )
        let allShardHashes = allShards.map(\.data)

        // Generate co-path justification
        let justificationSteps = try await erasureCodingService.generateJustification(
            shardIndex: shardIndex,
            segmentsRoot: d3lMetadata.segmentsRoot,
            shards: allShardHashes
        )
        let justification = AvailabilityJustification.copath(justificationSteps)

        return (bundleShard, segmentShards, justification)
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
        let requiredValidators = DataAvailabilityConstants.minimumValidatorResponses
        guard validators.count >= requiredValidators else {
            throw DataAvailabilityError.insufficientSignatures
        }

        // 2-5. TODO: Send requests, collect responses, verify, return
        // This requires network layer integration
        throw DataAvailabilityError.retrievalError
    }

    /// Process an incoming audit shard request (CE 138)
    /// - Parameters:
    ///   - erasureRoot: The erasure root
    ///   - shardIndex: The shard index
    /// - Returns: The bundle shard and justification
    public func processAuditShardRequest(
        erasureRoot: Data32,
        shardIndex: UInt16
    ) async throws -> (bundleShard: Data, justification: AvailabilityJustification) {
        // Reuse shardDistribution logic to get the shard and justification
        let (bundleShard, _, justification) = try await shardDistribution(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )

        return (bundleShard, justification)
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
    ///
    /// **CE 139→140 Fallback Pattern (per JAMNP-S spec):**
    /// - Initially use CE 139 (segment shard request without justification)
    /// - Verify reconstructed segment against its proof
    /// - If inconsistent, retry with CE 140 (with justification for each shard)
    ///
    /// The fallback logic should be implemented in the network layer (NetworkManager)
    /// where it can:
    /// 1. Send CE 139 requests (segmentShardRequest1)
    /// 2. Collect responses and verify segments
    /// 3. On verification failure, automatically retry with CE 140 (segmentShardRequest2)
    /// 4. Use justifications from CE 140 to validate shard correctness
    ///
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
        let requiredValidators = DataAvailabilityConstants.minimumValidatorResponses
        guard validators.count >= requiredValidators else {
            throw DataAvailabilityError.insufficientSignatures
        }

        // 2-5. TODO: Send requests, collect responses, verify, return
        // This requires network layer integration
        // Note: Implement CE 139→140 fallback pattern in NetworkManager
        throw DataAvailabilityError.retrievalError
    }

    /// Process an incoming segment shard request (CE 139/140)
    /// - Parameters:
    ///   - erasureRoot: The erasure root
    ///   - shardIndex: The shard index
    ///   - segmentIndices: The segment indices to fetch
    /// - Returns: The requested segment shards with justifications
    public func processSegmentShardRequest(
        erasureRoot: Data32,
        shardIndex: UInt16,
        segmentIndices: [UInt16]
    ) async throws -> [SegmentShard] {
        // 1. Get the full shard and base justification
        let (bundleShard, segmentShards, baseJustification) = try await shardDistribution(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )

        // 2. Extract requested segment shards and generate their justifications
        var result: [SegmentShard] = []

        // We need the bundle shard hash for segment justification
        let bundleShardHash = bundleShard.blake2b256hash()

        // We need base justification steps
        guard case let .copath(baseSteps) = baseJustification else {
            // If base justification is not copath, we might have a problem or it's a trivial case
            // For now assume copath
            throw DataAvailabilityError.invalidJustificationFormat
        }

        // Get D3L metadata for segments root
        guard let ecStore = erasureCodingDataStore,
              let d3lMetadata = try await ecStore.getD3LEntry(erasureRoot: erasureRoot)
        else {
            throw DataAvailabilityError.segmentsRootMappingNotFound
        }

        for segmentIndex in segmentIndices {
            // Find the segment shard for this segment index
            guard Int(segmentIndex) < segmentShards.count else {
                throw DataAvailabilityError.invalidSegmentIndex
            }

            let shardData = segmentShards[Int(segmentIndex)]

            let steps = try await erasureCodingService.generateSegmentJustification(
                segmentIndex: segmentIndex,
                bundleShardHash: bundleShardHash,
                shardIndex: shardIndex,
                segmentsRoot: d3lMetadata.segmentsRoot,
                shards: segmentShards,
                baseJustification: baseSteps
            )

            // Convert steps to JustificationStep
            let justificationSteps = steps.map { step -> JustificationStep in
                switch step {
                case let .left(hash): .left(hash)
                case let .right(hash): .right(hash)
                }
            }

            let justification = Justification.copath(justificationSteps)

            result.append(SegmentShard(shard: shardData, justification: justification))
        }

        return result
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
}
