import Codec
import Foundation
import Networking
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
    case segmentsRootMismatch(calculated: Data32, expected: Data32)
}

public final class DataAvailabilityService: ServiceBase2, @unchecked Sendable, OnSyncCompleted {
    private let dataProvider: BlockchainDataProvider
    private let dataStore: DataStore
    private let erasureCodingDataStore: ErasureCodingDataStore?
    private var networkClient: AvailabilityNetworkClient?
    private let erasureCodingService: ErasureCodingService

    public init(
        config: ProtocolConfigRef,
        eventBus: EventBus,
        scheduler: Scheduler,
        dataProvider: BlockchainDataProvider,
        dataStore: DataStore,
        erasureCodingDataStore: ErasureCodingDataStore? = nil,
        networkClient: AvailabilityNetworkClient? = nil
    ) async {
        self.dataProvider = dataProvider
        self.dataStore = dataStore
        self.erasureCodingDataStore = erasureCodingDataStore
        self.networkClient = networkClient
        erasureCodingService = ErasureCodingService(config: config)

        super.init(id: "DataAvailability", config: config, eventBus: eventBus, scheduler: scheduler)

        // Schedule regular purging of old data
        scheduleForNextEpoch("DataAvailability.scheduleForNextEpoch") { [weak self] epoch in
            await self?.purge(epoch: epoch)
        }
    }

    /// Set the network client for fetching missing shards
    public func setNetworkClient(_ client: AvailabilityNetworkClient) async {
        networkClient = client
        await erasureCodingDataStore?.setNetworkClient(client)
    }

    /// Set the fetch strategy for network operations
    public func setFetchStrategy(_ strategy: FetchStrategy) async {
        await erasureCodingDataStore?.setFetchStrategy(strategy)
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

        // Use ErasureCodingDataStore if available for efficient cleanup
        if let ecStore = erasureCodingDataStore {
            do {
                // Purge old audit store data (short-term storage, kept until finality, approximately 1 hour)
                // Assuming approximately 6 epochs per hour at 10 minutes per epoch
                let auditRetentionEpochs: EpochIndex = DataAvailabilityConstants.auditRetentionEpochs

                if epoch > auditRetentionEpochs {
                    let auditCutoffEpoch = epoch - auditRetentionEpochs
                    let (deleted, bytes) = try await ecStore.cleanupAuditEntriesBeforeEpoch(cutoffEpoch: auditCutoffEpoch)
                    logger.info("Purged \(deleted) audit entries (\(bytes) bytes) from epochs before \(auditCutoffEpoch)")
                }

                // Purge old import/D3L store data (long-term storage, kept for 28 days = 672 epochs)
                let d3lRetentionEpochs: EpochIndex = DataAvailabilityConstants.d3lRetentionEpochs

                if epoch > d3lRetentionEpochs {
                    let d3lCutoffEpoch = epoch - d3lRetentionEpochs
                    let (entriesDeleted, segmentsDeleted) = try await ecStore.cleanupD3LEntriesBeforeEpoch(cutoffEpoch: d3lCutoffEpoch)
                    logger.info("Purged \(entriesDeleted) D³L entries (\(segmentsDeleted) segments) from epochs before \(d3lCutoffEpoch)")
                }
            } catch {
                logger.error("Failed to purge old data: \(error)")
            }
        } else {
            // Fallback to timestamp-based approach for legacy DataStore
            // Assuming 1 hour for audit data, 28 days for D3L data
            let currentTimestamp = Date()
            let auditCutoffTime = currentTimestamp.addingTimeInterval(-3600) // 1 hour ago
            let d3lCutoffTime = currentTimestamp.addingTimeInterval(-28 * 24 * 3600) // 28 days ago

            // TODO: Implement timestamp-based cleanup when DataStore exposes iteration methods
            _ = (auditCutoffTime, d3lCutoffTime)
        }
    }

    /// Get cleanup metrics
    /// - Returns: Cleanup metrics if ErasureCodingDataStore is available
    public func getCleanupMetrics() async -> CleanupMetrics? {
        guard let ecStore = erasureCodingDataStore else {
            return nil
        }
        return await ecStore.getCleanupMetrics()
    }

    /// Reset cleanup metrics
    public func resetCleanupMetrics() async {
        await erasureCodingDataStore?.resetCleanupMetrics()
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
                segmentsRoot: segmentRoot
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

            // Store using ErasureCodingDataStore (handles erasure coding automatically)
            let erasureRoot = try await ecStore.storeAuditBundle(
                bundle: serializedData,
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot
            )

            logger.info("Stored audit bundle: erasureRoot=\(erasureRoot.toHexString()), size=\(serializedData.count)")

            return (erasureRoot: erasureRoot, length: dataLength)
        }

        // Fallback to legacy implementation
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
        validator validatorIndex: ValidatorIndex,
        requestData: Data
    ) async throws -> Data {
        // Ensure network client is available
        guard let networkClient else {
            logger.error("Network client not available for validator request")
            throw DataAvailabilityError.retrievalError
        }

        // Get validator's network address from on-chain state
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let validators = state.value.currentValidators

        // Check validator index is valid
        guard validatorIndex < UInt32(validators.count) else {
            logger.error("Validator index \(validatorIndex) out of range (0..<\(validators.count))")
            throw DataAvailabilityError.retrievalError
        }

        // Get the validator's network address from metadata
        let validator = validators[Int(validatorIndex)]
        let networkAddress = try extractNetworkAddress(from: validator.metadata.data)

        // Send request via network client
        logger.debug("Sending request to validator \(validatorIndex) at \(networkAddress)")

        do {
            guard let networkProtocol = await networkClient.getNetwork() else {
                logger.error("Network protocol not available in network client")
                throw DataAvailabilityError.retrievalError
            }

            let responses = try await networkProtocol.send(to: networkAddress, data: requestData)

            // Return first response (most protocols return single response)
            guard let response = responses.first else {
                logger.error("No response from validator \(validatorIndex)")
                throw DataAvailabilityError.retrievalError
            }

            return response
        } catch {
            logger.error("Failed to fetch from validator \(validatorIndex): \(error)")
            throw DataAvailabilityError.retrievalError
        }
    }

    /// Extract network address from validator metadata
    /// - Parameter metadata: Validator metadata bytes
    /// - Returns: Network address
    /// - Throws: DataAvailabilityError if extraction fails
    private func extractNetworkAddress(from metadata: Data) throws -> NetAddr {
        // Metadata format: <multiaddr> (see GP spec)
        // For now, we assume it's encoded in the metadata
        // TODO: Implement proper multiaddr decoding per spec
        // This is a placeholder that needs proper multiaddr parsing

        // For testing purposes, try to create address from metadata
        // In production, this should parse the multiaddr format properly
        let metadataString = metadata.toHexString()

        // Try common formats
        if let addr = NetAddr(address: metadataString) {
            return addr
        }

        // If metadata contains a valid IPv4:port format
        // Format: /ip4/<ip>/tcp/<port>
        if metadataString.hasPrefix("/ip4/") {
            let parts = metadataString.components(separatedBy: "/")
            if parts.count >= 5, let ip = parts[safe: 2], let port = parts[safe: 4] {
                let addrString = "\(ip):\(port)"
                if let addr = NetAddr(address: addrString) {
                    return addr
                }
            }
        }

        // Fallback to localhost for testing
        // TODO: Remove this fallback and implement proper multiaddr parsing
        logger.warning("Unable to parse network address from metadata, using localhost fallback")
        return NetAddr(address: "127.0.0.1:0")!
    }

    /// Fetch shards from multiple validators concurrently
    /// - Parameters:
    ///   - validators: The validators to fetch from
    ///   - shardRequest: The shard request data
    /// - Returns: The collected shard responses
    /// - Throws: DataAvailabilityError if insufficient validators respond
    public func fetchFromValidatorsConcurrently(
        validators validatorIndices: [ValidatorIndex],
        shardRequest: Data
    ) async throws -> [(validator: ValidatorIndex, data: Data)] {
        // Fetch from validators concurrently with timeout
        // We need at least minimumValidatorResponses validators to respond for successful reconstruction
        let requiredResponses = DataAvailabilityConstants.minimumValidatorResponses

        logger.debug("Fetching from \(validatorIndices.count) validators concurrently (need \(requiredResponses) responses)")

        var responses: [(validator: ValidatorIndex, data: Data)] = []

        await withTaskGroup(of: (ValidatorIndex, Data?).self) { group in
            for validator in validatorIndices {
                group.addTask { [weak self] in
                    guard let self else {
                        return (validator, nil)
                    }
                    do {
                        let data = try await fetchFromValidator(validator: validator, requestData: shardRequest)
                        return (validator, data)
                    } catch {
                        logger.warning("Failed to fetch from validator \(validator): \(error)")
                        return (validator, nil)
                    }
                }
            }

            for await (validator, data) in group {
                if let data {
                    responses.append((validator, data))
                    logger.debug("Received response from validator \(validator) (\(responses.count)/\(requiredResponses))")

                    // Early exit if we have enough responses
                    if responses.count >= requiredResponses {
                        group.cancelAll()
                        break
                    }
                }
            }
        }

        guard responses.count >= requiredResponses else {
            logger.error("Insufficient validator responses: \(responses.count)/\(requiredResponses)")
            throw DataAvailabilityError.retrievalError
        }

        logger.info("Successfully fetched data from \(responses.count) validators")
        return responses
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
            try await validate(signatures: signatures, workReportHash: hash)

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
        // Where Xguarantee is the string "$jam_guarantee" with a length prefix byte
        let guaranteePrefix = Data("\u{10}$jam_guarantee".utf8)
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
            // Where Xguarantee is the string "$jam_guarantee"
            let guaranteePrefix = Data("\u{10}$jam_guarantee".utf8)
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
            // CE 137: Respond with bundle shard and segment shards with justification

            // Use ErasureCodingDataStore if available
            if let ecStore = erasureCodingDataStore {
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
                guard let auditMetadata = try await ecStore.getAuditEntry(erasureRoot: erasureRoot) else {
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
                let allShardIndices = Array(0 ..< 1023).map { UInt16($0) }
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

                // Respond with bundle shard + segment shards + justification
                publish(RuntimeEvents.ShardDistributionReceivedResponse(
                    requestId: requestId,
                    bundleShard: bundleShard,
                    segmentShards: segmentShards,
                    justification: justification
                ))

            } else {
                // Fallback: throw error since we can't generate proper justification
                throw DataAvailabilityError.segmentNotFound
            }

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
        return try generateJustificationFromMerklePath(from: merklePath, shardIndex: shardIndex, segmentShards: segmentShards)
    }

    /// Generate justification from Merkle path
    private func generateJustificationFromMerklePath(
        from merklePath: [Either<Data, Data32>],
        shardIndex: UInt16,
        segmentShards: [Data]
    ) throws -> Justification {
        switch merklePath.count {
        case 1:
            try generateSingleHashJustification(from: merklePath)
        case 2:
            try generateDoubleHashJustification(from: merklePath)
        default:
            try generateSegmentShardJustification(shardIndex: shardIndex, segmentShards: segmentShards)
        }
    }

    /// Generate single hash justification for shallow trees
    private func generateSingleHashJustification(from merklePath: [Either<Data, Data32>]) throws -> Justification {
        guard case let .right(hash) = merklePath.first else {
            throw DataAvailabilityError.invalidMerklePath
        }
        return .singleHash(hash)
    }

    /// Generate double hash justification for medium depth trees
    private func generateDoubleHashJustification(from merklePath: [Either<Data, Data32>]) throws -> Justification {
        guard case let .right(hash1) = merklePath[0],
              case let .right(hash2) = merklePath[1]
        else {
            throw DataAvailabilityError.invalidMerklePath
        }
        return .doubleHash(hash1, hash2)
    }

    /// Generate segment shard justification for deep trees
    private func generateSegmentShardJustification(
        shardIndex: UInt16,
        segmentShards: [Data]
    ) throws -> Justification {
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
            let signatureMessage = try JamEncoder.encode(Data("\u{10}$jam_available".utf8), message)

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
            let signatureMessage = try JamEncoder.encode(Data("\u{10}$jam_available".utf8), message)

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

    /// Batch reconstruction with network fallback
    /// - Parameters:
    ///   - erasureRoots: Erasure roots to reconstruct
    ///   - originalLengths: Mapping of erasure root to original length
    ///   - validatorAddresses: Optional dictionary of validator index to network address
    ///   - coreIndex: Core index for shard assignment (default: 0)
    ///   - totalValidators: Total number of validators (default: 1023)
    /// - Returns: Dictionary mapping erasure root to reconstructed data
    /// - Throws: DataAvailabilityError if reconstruction fails
    public func batchReconstructWithFallback(
        erasureRoots: [Data32],
        originalLengths: [Data32: Int],
        validatorAddresses: [UInt16: NetAddr]? = nil,
        coreIndex: UInt16 = 0,
        totalValidators: UInt16 = 1023
    ) async throws -> [Data32: Data] {
        guard let ecStore = erasureCodingDataStore else {
            throw DataAvailabilityError.retrievalError
        }

        // Convert validator addresses from NetAddr if needed
        var addresses: [UInt16: NetAddr] = [:]
        if let validatorAddresses {
            addresses = validatorAddresses
        }

        return try await ecStore.batchReconstruct(
            erasureRoots: erasureRoots,
            originalLengths: originalLengths,
            validators: addresses.isEmpty ? nil : addresses,
            coreIndex: coreIndex,
            totalValidators: totalValidators
        )
    }

    /// Fetch segments with network fallback
    /// - Parameters:
    ///   - erasureRoot: Erasure root identifying the data
    ///   - indices: Segment indices to retrieve
    ///   - validatorAddresses: Optional dictionary of validator index to network address
    ///   - coreIndex: Core index for shard assignment (default: 0)
    ///   - totalValidators: Total number of validators (default: 1023)
    /// - Returns: Array of segments
    /// - Throws: DataAvailabilityError if retrieval fails
    public func fetchSegmentsWithFallback(
        erasureRoot: Data32,
        indices: [Int],
        validatorAddresses: [UInt16: NetAddr]? = nil,
        coreIndex: UInt16 = 0,
        totalValidators: UInt16 = 1023
    ) async throws -> [Data4104] {
        guard let ecStore = erasureCodingDataStore else {
            throw DataAvailabilityError.segmentNotFound
        }

        return try await ecStore.getSegmentsWithNetworkFallback(
            erasureRoot: erasureRoot,
            indices: indices,
            validators: validatorAddresses,
            coreIndex: coreIndex,
            totalValidators: totalValidators
        )
    }

    // MARK: - Shard Management

    /// Get local shard availability for an erasure root
    /// - Parameter erasureRoot: The erasure root to check
    /// - Returns: Number of locally available shards
    public func getLocalShardCount(erasureRoot: Data32) async -> Int {
        guard let ecStore = erasureCodingDataStore else {
            logger.warning("ErasureCodingDataStore not available")
            return 0
        }

        do {
            return try await ecStore.getLocalShardCount(erasureRoot: erasureRoot)
        } catch {
            logger.error("Failed to get local shard count: \(error)")
            return 0
        }
    }

    /// Calculate reconstruction potential
    /// - Parameter erasureRoot: The erasure root to check
    /// - Returns: True if we have enough shards for reconstruction (>= 342)
    public func canReconstruct(erasureRoot: Data32) async -> Bool {
        guard let ecStore = erasureCodingDataStore else {
            return false
        }

        do {
            return try await ecStore.canReconstructLocally(erasureRoot: erasureRoot)
        } catch {
            logger.error("Failed to check reconstruction capability: \(error)")
            return false
        }
    }

    /// Get missing shard indices for an erasure root
    /// - Parameter erasureRoot: The erasure root to check
    /// - Returns: Array of missing shard indices
    public func getMissingShardIndices(erasureRoot: Data32) async -> [UInt16] {
        guard let ecStore = erasureCodingDataStore else {
            logger.warning("ErasureCodingDataStore not available")
            return []
        }

        do {
            return try await ecStore.getMissingShardIndices(erasureRoot: erasureRoot)
        } catch {
            logger.error("Failed to get missing shard indices: \(error)")
            return []
        }
    }

    /// Get reconstruction plan for an erasure root
    /// - Parameter erasureRoot: The erasure root to check
    /// - Returns: Reconstruction plan with detailed information
    public func getReconstructionPlan(erasureRoot: Data32) async -> ReconstructionPlan? {
        guard let ecStore = erasureCodingDataStore else {
            logger.warning("ErasureCodingDataStore not available")
            return nil
        }

        do {
            return try await ecStore.getReconstructionPlan(erasureRoot: erasureRoot)
        } catch {
            logger.error("Failed to get reconstruction plan: \(error)")
            return nil
        }
    }

    /// Fetch segments with automatic reconstruction if needed
    /// - Parameters:
    ///   - erasureRoot: The erasure root identifying the data
    ///   - indices: Segment indices to fetch
    /// - Returns: Array of segments
    public func fetchSegments(erasureRoot: Data32, indices: [Int]) async throws -> [Data4104] {
        guard let ecStore = erasureCodingDataStore else {
            throw DataAvailabilityError.segmentNotFound
        }

        // Try fetching with cache first
        return try await ecStore.getSegmentsWithCache(erasureRoot: erasureRoot, indices: indices)
    }

    /// Reconstruct data from local shards
    /// - Parameters:
    ///   - erasureRoot: The erasure root identifying the data
    ///   - originalLength: Original data length
    /// - Returns: Reconstructed data
    public func reconstructFromLocalShards(erasureRoot: Data32, originalLength: Int) async throws -> Data {
        guard let ecStore = erasureCodingDataStore else {
            throw DataAvailabilityError.segmentNotFound
        }

        return try await ecStore.reconstructFromLocalShards(
            erasureRoot: erasureRoot,
            originalLength: originalLength
        )
    }

    // MARK: - Statistics and Monitoring

    /// Get data availability statistics
    /// - Returns: Statistics about stored data
    public func getStatistics() async -> (auditStoreCount: Int, importStoreCount: Int, totalSegments: Int) {
        // TODO: Implement once DataStore supports statistics
        // For now, return zeros
        (0, 0, 0)
    }

    /// Get cache statistics
    /// - Returns: Cache statistics including hits, misses, evictions, size, and hit rate
    public func getCacheStatistics() async -> (hits: Int, misses: Int, evictions: Int, size: Int, hitRate: Double)? {
        guard let ecStore = erasureCodingDataStore else {
            return nil
        }

        return await ecStore.getCacheStatistics()
    }

    /// Clear cache for a specific erasure root
    /// - Parameter erasureRoot: The erasure root to clear cache for
    public func clearCache(erasureRoot: Data32) async {
        await erasureCodingDataStore?.clearCache(erasureRoot: erasureRoot)
    }

    /// Clear all cache
    public func clearAllCache() async {
        await erasureCodingDataStore?.clearAllCache()
    }

    /// Get storage usage information
    /// - Returns: Storage usage in bytes
    public func getStorageUsage() async -> (auditStore: Int, importStore: Int) {
        // TODO: Implement once DataStore supports size queries or add to ErasureCodingDataStore
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
