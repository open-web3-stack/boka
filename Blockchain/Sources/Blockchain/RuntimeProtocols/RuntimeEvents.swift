import Codec
import Foundation
import Utils

public enum RuntimeEvents {
    public struct StateRequestReceived: Event {
        public var headerHash: Data32
        public var startKey: Data31
        public var endKey: Data31
        public var maxSize: UInt32

        public init(headerHash: Data32, startKey: Data31, endKey: Data31, maxSize: UInt32) {
            self.headerHash = headerHash
            self.startKey = startKey
            self.endKey = endKey
            self.maxSize = maxSize
        }

        public func generateRequestId() throws -> Data32 {
            let encoder = JamEncoder()
            try encoder.encode(headerHash)
            try encoder.encode(startKey)
            try encoder.encode(endKey)
            try encoder.encode(maxSize)
            return encoder.data.blake2b256hash()
        }
    }

    public struct StateRequestReceivedResponse: Event {
        public var requestId: Data32
        public let result: Result<(headerHash: Data32, boundaryNodes: [BoundaryNode], keyValuePairs: [(key: Data31, value: Data)]), Error>

        public init(requestId: Data32, headerHash: Data32, boundaryNodes: [BoundaryNode], keyValuePairs: [(key: Data31, value: Data)]) {
            self.requestId = requestId
            result = .success((headerHash, boundaryNodes, keyValuePairs))
        }

        public init(requestId: Data32, error: Error) {
            self.requestId = requestId
            result = .failure(error)
        }
    }

    public struct BlockImported: Event {
        public let block: BlockRef
        public let state: StateRef
        public let parentState: StateRef

        public init(block: BlockRef, state: StateRef, parentState: StateRef) {
            self.block = block
            self.state = state
            self.parentState = parentState
        }
    }

    public struct BlockFinalized: Event {
        public let hash: Data32

        public init(hash: Data32) {
            self.hash = hash
        }
    }

    // Called before an epoch change is expected on next timeslot
    // Note: This is only called when under as validator mode
    public struct BeforeEpochChange: Event {
        public let epoch: EpochIndex
        public let state: SafrolePostState

        public init(epoch: EpochIndex, state: SafrolePostState) {
            self.epoch = epoch
            self.state = state
        }
    }

    // New safrole ticket generated from SafroleService
    public struct SafroleTicketsGenerated: Event {
        public let epochIndex: EpochIndex
        public let items: [TicketItemAndOutput]
        public let publicKey: Bandersnatch.PublicKey

        public init(
            epochIndex: EpochIndex,
            items: [TicketItemAndOutput],
            publicKey: Bandersnatch.PublicKey
        ) {
            self.epochIndex = epochIndex
            self.items = items
            self.publicKey = publicKey
        }
    }

    // New safrole ticket received from network
    public struct SafroleTicketsReceived: Event {
        public let items: [ExtrinsicTickets.TicketItem]

        public init(items: [ExtrinsicTickets.TicketItem]) {
            self.items = items
        }
    }

    // New block authored by BlockAuthor service
    public struct BlockAuthored: Event {
        public let block: BlockRef
    }

    // RPC -> NetworkManager & GuaranteeingService: Received new work package submission via RPC
    public struct WorkPackagesSubmitted: Event {
        public let coreIndex: CoreIndex
        public let workPackage: WorkPackageRef
        public let extrinsics: [Data]

        public init(coreIndex: CoreIndex, workPackage: WorkPackageRef, extrinsics: [Data]) {
            self.coreIndex = coreIndex
            self.workPackage = workPackage
            self.extrinsics = extrinsics
        }
    }

    // NetworkManager -> GuaranteeingService: When a work package is received via CE133
    public struct WorkPackagesReceived: Event {
        public let coreIndex: CoreIndex
        public let workPackage: WorkPackageRef
        public let extrinsics: [Data]

        public init(coreIndex: CoreIndex, workPackage: WorkPackageRef, extrinsics: [Data]) {
            self.coreIndex = coreIndex
            self.workPackage = workPackage
            self.extrinsics = extrinsics
        }
    }

    // GuaranteeingService -> NetworkManager: When a work package bundle is ready to shared via CE134
    public struct WorkPackageBundleReady: Event {
        public let target: Ed25519PublicKey
        public let coreIndex: CoreIndex
        public let bundle: WorkPackageBundle
        public let segmentsRootMappings: SegmentsRootMappings

        public init(
            target: Ed25519PublicKey,
            coreIndex: CoreIndex,
            bundle: WorkPackageBundle,
            segmentsRootMappings: SegmentsRootMappings
        ) {
            self.target = target
            self.coreIndex = coreIndex
            self.bundle = bundle
            self.segmentsRootMappings = segmentsRootMappings
        }
    }

    // NetworkManager -> GuaranteeingService: When a work package bundle is recived via CE134 request
    public struct WorkPackageBundleReceived: Event {
        public let coreIndex: CoreIndex
        public let segmentsRootMappings: SegmentsRootMappings
        public let bundle: WorkPackageBundle

        public init(
            coreIndex: CoreIndex,
            bundle: WorkPackageBundle,
            segmentsRootMappings: SegmentsRootMappings
        ) {
            self.coreIndex = coreIndex
            self.bundle = bundle
            self.segmentsRootMappings = segmentsRootMappings
        }
    }

    // GuaranteeingService -> NetworkManager: Response to CE134 request
    public struct WorkPackageBundleReceivedResponse: Event {
        public let workBundleHash: Data32
        public let result: Result<(workReportHash: Data32, signature: Ed25519Signature), Error>

        public init(
            workBundleHash: Data32,
            workReportHash: Data32,
            signature: Ed25519Signature
        ) {
            self.workBundleHash = workBundleHash
            result = .success((workReportHash, signature))
        }

        public init(
            workBundleHash: Data32,
            error: Error
        ) {
            self.workBundleHash = workBundleHash
            result = .failure(error)
        }
    }

    // NetworkManager -> GuaranteeingService: When a work package bundle response is recived via CE134 reply
    public struct WorkPackageBundleReceivedReply: Event {
        public let source: Ed25519PublicKey
        public let workReportHash: Data32
        public let signature: Ed25519Signature

        public init(
            source: Ed25519PublicKey,
            workReportHash: Data32,
            signature: Ed25519Signature
        ) {
            self.source = source
            self.workReportHash = workReportHash
            self.signature = signature
        }
    }

    // A guaranteed work-report ready for distribution via CE135.
    public struct WorkReportGenerated: Event {
        public let workReport: WorkReport
        public let slot: UInt32
        public var signatures: [ValidatorSignature]

        public init(
            workReport: WorkReport,
            slot: UInt32,
            signatures: [ValidatorSignature]
        ) {
            self.workReport = workReport
            self.slot = slot
            self.signatures = signatures
        }
    }

    // When a work report is received via CE135
    public struct WorkReportReceived: Event {
        public let workReport: WorkReport
        public let slot: UInt32
        public var signatures: [ValidatorSignature]

        public init(
            workReport: WorkReport,
            slot: UInt32,
            signatures: [ValidatorSignature]
        ) {
            self.workReport = workReport
            self.slot = slot
            self.signatures = signatures
        }
    }

    public struct WorkReportRequestReceived: Event {
        public let workReportHash: Data32

        public init(workReportHash: Data32) {
            self.workReportHash = workReportHash
        }
    }

    public struct WorkReportRequestReady: Event {
        public let source: Ed25519PublicKey
        public let workReportHash: Data32

        public init(source: Ed25519PublicKey, workReportHash: Data32) {
            self.source = source
            self.workReportHash = workReportHash
        }
    }

    public struct ShardDistributionReceived: Event {
        public var erasureRoot: Data32
        public var shardIndex: UInt32

        public init(erasureRoot: Data32, shardIndex: UInt32) {
            self.erasureRoot = erasureRoot
            self.shardIndex = shardIndex
        }

        public func generateRequestId() throws -> Data32 {
            let encoder = JamEncoder()
            try encoder.encode(erasureRoot)
            try encoder.encode(shardIndex)
            return encoder.data.blake2b256hash()
        }
    }

    public struct ShardDistributionReady: Event {
        public let source: Ed25519PublicKey
        public var erasureRoot: Data32
        public var shardIndex: UInt32

        public init(source: Ed25519PublicKey, erasureRoot: Data32, shardIndex: UInt32) {
            self.source = source
            self.erasureRoot = erasureRoot
            self.shardIndex = shardIndex
        }
    }

    //  Response to shard distribution
    public struct ShardDistributionReceivedResponse: Event {
        public var requestId: Data32

        public let result: Result<(bundleShard: Data, segmentShards: [Data], justification: Justification), Error>

        public init(requestId: Data32, bundleShard: Data, segmentShards: [Data], justification: Justification) {
            self.requestId = requestId
            result = .success((bundleShard, segmentShards, justification))
        }

        public init(requestId: Data32, error: Error) {
            self.requestId = requestId
            result = .failure(error)
        }
    }

    //  Response to work report request
    public struct WorkReportRequestResponse: Event {
        public var workReportHash: Data32

        public let result: Result<WorkReport, Error>

        public init(workReportHash: Data32, workReport: WorkReport) {
            self.workReportHash = workReportHash
            result = .success(workReport)
        }

        public init(workReportHash: Data32, error: Error) {
            self.workReportHash = workReportHash
            result = .failure(error)
        }
    }

    public struct AuditShardRequestReceived: Event {
        public let erasureRoot: Data32
        public let shardIndex: UInt32

        public init(erasureRoot: Data32, shardIndex: UInt32) {
            self.erasureRoot = erasureRoot
            self.shardIndex = shardIndex
        }

        public func generateRequestId() throws -> Data32 {
            let encoder = JamEncoder()
            try encoder.encode(erasureRoot)
            try encoder.encode(shardIndex)
            return encoder.data.blake2b256hash()
        }
    }

    public struct AuditShardRequestReceivedResponse: Event {
        public var requestId: Data32

        public let result: Result<(erasureRoot: Data32, shardIndex: UInt32, bundleShard: Data, justification: Justification), Error>

        public init(requestId: Data32, erasureRoot: Data32, shardIndex: UInt32, bundleShard: Data, justification: Justification) {
            self.requestId = requestId
            result = .success((erasureRoot, shardIndex, bundleShard, justification))
        }

        public init(requestId: Data32, error: Error) {
            self.requestId = requestId
            result = .failure(error)
        }
    }

    public struct SegmentShardRequestReceived: Event {
        public let erasureRoot: Data32
        public let shardIndex: UInt32
        public let segmentIndices: [UInt16]

        public init(
            erasureRoot: Data32,
            shardIndex: UInt32,
            segmentIndices: [UInt16]
        ) {
            self.erasureRoot = erasureRoot
            self.shardIndex = shardIndex
            self.segmentIndices = segmentIndices
        }

        public func generateRequestId() throws -> Data32 {
            let encoder = JamEncoder()
            try encoder.encode(erasureRoot)
            try encoder.encode(shardIndex)
            try encoder.encode(UInt32(segmentIndices.count))
            try encoder.encode(segmentIndices)
            return encoder.data.blake2b256hash()
        }
    }

    public struct SegmentShardRequestReceivedResponse: Event {
        public let requestId: Data32
        public let result: Result<[SegmentShard], Error>

        public init(
            requestId: Data32,
            segments: [SegmentShard]
        ) {
            self.requestId = requestId
            result = .success(segments)
        }

        public init(
            requestId: Data32,
            error: Error
        ) {
            self.requestId = requestId
            result = .failure(error)
        }
    }

    public struct AssuranceDistributionReceived: Event {
        public let headerHash: Data32
        public let bitfield: Data // (One bit per core)
        public let signature: Ed25519Signature

        public init(headerHash: Data32, bitfield: Data, signature: Ed25519Signature) {
            self.headerHash = headerHash
            self.bitfield = bitfield
            self.signature = signature
        }
    }

    public struct PreimageAnnouncementReceived: Event {
        public let serviceID: UInt32
        public let hash: Data32
        public let preimageLength: UInt32

        public init(serviceID: UInt32, hash: Data32, preimageLength: UInt32) {
            self.serviceID = serviceID
            self.hash = hash
            self.preimageLength = preimageLength
        }
    }

    public struct PreimageRequestReceived: Event {
        public let hash: Data32

        public init(hash: Data32) {
            self.hash = hash
        }
    }

    public struct PreimageRequestReceivedResponse: Event {
        public let hash: Data32
        public let result: Result<Data, Error>

        public init(hash: Data32, preimage: Data) {
            self.hash = hash
            result = .success(preimage)
        }

        public init(hash: Data32, error: Error) {
            self.hash = hash
            result = .failure(error)
        }
    }

    public struct JudgementPublicationReceived: Event {
        public let epochIndex: EpochIndex
        public let validatorIndex: ValidatorIndex
        public let validity: UInt8 // 0 = Invalid, 1 = Valid
        public let workReportHash: Data32
        public let signature: Ed25519Signature

        public init(
            epochIndex: EpochIndex,
            validatorIndex: ValidatorIndex,
            validity: UInt8,
            workReportHash: Data32,
            signature: Ed25519Signature
        ) {
            self.epochIndex = epochIndex
            self.validatorIndex = validatorIndex
            self.validity = validity
            self.workReportHash = workReportHash
            self.signature = signature
        }
    }
}
