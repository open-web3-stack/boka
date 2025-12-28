import Blockchain
import Codec
import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "NetworkManager")

let MAX_BLOCKS_PER_REQUEST: UInt32 = 50

enum BroadcastTarget {
    case safroleStep1Validator
    case currentValidators
}

enum NetworkManagerError: Error {
    case peerNotFound
    case unimplemented(String)
}

private actor NetworkManagerStorage {
    var peerIdByPublicKey: [Data32: PeerId] = [:]

    func getPeerId(publicKey: Data32) -> PeerId? {
        peerIdByPublicKey[publicKey]
    }

    func set(_ dict: [Data32: PeerId]) {
        peerIdByPublicKey = dict
    }
}

// TODO: move validator only code to a separate class
public final class NetworkManager: Sendable {
    public let peerManager: PeerManager
    public let network: any NetworkProtocol
    public let syncManager: SyncManager
    public let blockchain: Blockchain
    private let subscriptions: EventSubscriptions

    // This is for development only
    // Those peers will receive all the messages regardless the target
    private let devPeers: Set<Either<PeerId, NetAddr>>

    private let storage = NetworkManagerStorage()

    public init(
        buildNetwork: (NetworkProtocolHandler) throws -> any NetworkProtocol,
        blockchain: Blockchain,
        eventBus: EventBus,
        devPeers: Set<NetAddr>
    ) async throws {
        peerManager = PeerManager(eventBus: eventBus)
        network = try buildNetwork(HandlerImpl(blockchain: blockchain, peerManager: peerManager))
        syncManager = SyncManager(
            blockchain: blockchain, network: network, peerManager: peerManager, eventBus: eventBus
        )
        self.blockchain = blockchain

        subscriptions = EventSubscriptions(eventBus: eventBus)

        var selfDevPeers = Set<Either<PeerId, NetAddr>>()

        logger.info("P2P Listening on \(try! network.listenAddress())")

        for peer in devPeers {
            let conn = try network.connect(to: peer, role: .validator)
            try? await conn.ready()
            let pubkey = conn.publicKey
            if let pubkey {
                selfDevPeers.insert(.left(PeerId(publicKey: pubkey, address: peer)))
            } else {
                // unable to connect, add as address
                selfDevPeers.insert(.right(peer))
            }
        }

        self.devPeers = selfDevPeers

        Task {
            await subscriptions.subscribe(
                RuntimeEvents.SafroleTicketsGenerated.self,
                id: "NetworkManager.SafroleTicketsGenerated"
            ) { [weak self] event in
                await self?.on(safroleTicketsGenerated: event)
            }

            await subscriptions.subscribe(
                RuntimeEvents.BlockImported.self,
                id: "NetworkManager.BlockImported"
            ) { [weak self] event in
                await self?.on(blockImported: event)
            }

            await subscriptions.subscribe(
                RuntimeEvents.WorkPackagesSubmitted.self,
                id: "NetworkManager.WorkPackagesSubmitted"
            ) { [weak self] event in
                await self?.on(workPackagesSubmitted: event)
            }

            await subscriptions.subscribe(
                RuntimeEvents.WorkPackageBundleReady.self,
                id: "NetworkManager.WorkPackageBundleReady"
            ) { [weak self] event in
                await self?.on(workPackageBundleReady: event)
            }

            await subscriptions.subscribe(
                RuntimeEvents.BeforeEpochChange.self,
                id: "NetworkManager.BeforeEpochChange"
            ) { [weak self] event in
                await self?.on(beforeEpochChange: event)
            }

            await subscriptions.subscribe(
                RuntimeEvents.WorkReportGenerated.self,
                id: "NetworkManager.WorkReportGenerated"
            ) { [weak self] event in
                await self?.on(workReportGenerated: event)
            }
        }
    }

    private func getAddresses(target: BroadcastTarget) -> Set<Either<PeerId, NetAddr>> {
        // TODO: get target from onchain state
        switch target {
        case .safroleStep1Validator:
            // TODO: only send to the selected validator in the spec
            devPeers
        case .currentValidators:
            // TODO: read onchain state for validators
            devPeers
        }
    }

    private func send(to: Ed25519PublicKey, message: CERequest) async throws -> [Data] {
        guard let peerId = await storage.getPeerId(publicKey: to) else {
            throw NetworkManagerError.peerNotFound
        }
        return try await network.send(to: peerId, message: message)
    }

    private func send(to: PeerId, message: CERequest) async throws -> [Data] {
        try await network.send(to: to, message: message)
    }

    private func broadcast(
        to: BroadcastTarget,
        message: CERequest,
        responseHandler: @Sendable @escaping (Result<[Data], Error>) async -> Void
    ) async {
        let targets = getAddresses(target: to)
        for target in targets {
            Task {
                logger.trace("sending message", metadata: ["target": "\(target)", "message": "\(message)"])
                let res = await Result {
                    switch target {
                    case let .left(peerId):
                        try await network.send(to: peerId, message: message)
                    case let .right(address):
                        try await network.send(to: address, message: message)
                    }
                }
                await responseHandler(res)
            }
        }
    }

    private func broadcast(to: BroadcastTarget, message: CERequest) async {
        let targets = getAddresses(target: to)
        for target in targets {
            Task {
                logger.trace("sending message", metadata: ["target": "\(target)", "message": "\(message)"])
                // not expecting a response
                // TODO: handle errors and ensure no data is returned
                switch target {
                case let .left(peerId):
                    _ = try await network.send(to: peerId, message: message)
                case let .right(address):
                    _ = try await network.send(to: address, message: message)
                }
            }
        }
    }

    private func on(safroleTicketsGenerated event: RuntimeEvents.SafroleTicketsGenerated) async {
        logger.trace("sending tickets1", metadata: ["epochIndex": "\(event.epochIndex)"])
        for ticket in event.items {
            await broadcast(
                to: .safroleStep1Validator,
                message: .safroleTicket1(.init(
                    epochIndex: event.epochIndex,
                    attempt: ticket.ticket.attempt,
                    proof: ticket.ticket.signature
                ))
            )
        }
    }

    private func on(blockImported event: RuntimeEvents.BlockImported) async {
        logger.debug("sending blocks", metadata: ["hash": "\(event.block.hash)"])
        let finalized = await blockchain.dataProvider.finalizedHead
        network.broadcast(
            kind: .blockAnnouncement,
            message: .blockAnnouncement(BlockAnnouncement(
                header: event.block.header.asRef(),
                finalized: HashAndSlot(hash: finalized.hash, timeslot: finalized.timeslot)
            ))
        )
    }

    private func on(workPackagesSubmitted event: RuntimeEvents.WorkPackagesSubmitted) async {
        logger.trace("sending work package", metadata: ["coreIndex": "\(event.coreIndex)"])
        await broadcast(
            to: .currentValidators,
            message: .workPackageSubmission(.init(
                coreIndex: event.coreIndex,
                workPackage: event.workPackage.value,
                extrinsics: event.extrinsics
            ))
        )
    }

    private func on(workPackageBundleReady event: RuntimeEvents.WorkPackageBundleReady) async {
        await withSpan("NetworkManager.on(workPackageBundleReady)", logger: logger) { _ in
            let target = event.target

            let resp = try await send(to: target, message: .workPackageSharing(.init(
                coreIndex: event.coreIndex,
                segmentsRootMappings: event.segmentsRootMappings,
                bundle: event.bundle
            )))

            // <-- Work-Report Hash ++ Ed25519 Signature
            guard resp.count == 1, let data = resp.first else {
                logger.warning("WorkPackageSharing response is invalid", metadata: ["resp": "\(resp)", "target": "\(target)"])
                return
            }

            let decoder = JamDecoder(data: data, config: blockchain.config)
            let workReportHash = try decoder.decode(Data32.self)
            let signature = try decoder.decode(Ed25519Signature.self)

            blockchain.publish(event: RuntimeEvents.WorkPackageBundleReceivedReply(
                source: target,
                workReportHash: workReportHash,
                signature: signature
            ))
        }
    }

    // Note: This is only called when under as validator mode
    private func on(beforeEpochChange event: RuntimeEvents.BeforeEpochChange) async {
        await withSpan("NetworkManager.onBeforeEpoch", logger: logger) { _ in
            let currentValidators = event.state.currentValidators
            let nextValidators = event.state.nextValidators
            let allValidators = Set([currentValidators.array, nextValidators.array].joined())
            print("NetworkManager.onBeforeEpoch \(allValidators)")
            var peerIdByPublicKey: [Data32: PeerId] = [:]
            for validator in allValidators {
                if let addr = NetAddr(address: validator.metadataString) {
                    peerIdByPublicKey[validator.ed25519] = PeerId(
                        publicKey: validator.ed25519.data,
                        address: addr
                    )
                }
            }

            await storage.set(peerIdByPublicKey)
        }
    }

    private func on(workReportGenerated event: RuntimeEvents.WorkReportGenerated) async {
        logger.trace("sending guaranteed work-report",
                     metadata: ["slot": "\(event.slot)",
                                "signatures": "\(event.signatures.count)"])
        await broadcast(
            to: .currentValidators,
            message: .workReportDistribution(.init(
                workReport: event.workReport,
                slot: event.slot,
                signatures: event.signatures
            ))
        )
    }

    public var peersCount: Int {
        network.peersCount
    }
}

struct HandlerImpl: NetworkProtocolHandler {
    let blockchain: Blockchain
    let peerManager: PeerManager

    func handle(ceRequest: CERequest) async throws -> [Data] {
        logger.trace("handling request", metadata: ["request": "\(ceRequest)"])
        switch ceRequest {
        case let .blockRequest(message):
            let dataProvider = blockchain.dataProvider
            let count = min(MAX_BLOCKS_PER_REQUEST, message.maxBlocks)
            let encoder = JamEncoder()
            switch message.direction {
            case .ascendingExcludsive:
                let number = try await dataProvider.getBlockNumber(hash: message.hash)
                var currentHash = message.hash
                for i in 1 ... count {
                    let hashes = try await dataProvider.getBlockHash(byNumber: number + i)
                    var found = false
                    for hash in hashes {
                        let block = try await dataProvider.getBlock(hash: hash)
                        if block.header.parentHash == currentHash {
                            try encoder.encode(block)
                            found = true
                            currentHash = hash
                            break
                        }
                    }
                    if !found {
                        break
                    }
                }
            case .descendingInclusive:
                var hash = message.hash
                for _ in 0 ..< count {
                    let block = try await dataProvider.getBlock(hash: hash)
                    try encoder.encode(block)
                    if hash == dataProvider.genesisBlockHash {
                        break
                    }
                    hash = block.header.parentHash
                }
            }
            return [encoder.data]
        case let .bundleRequest(message):
            // CE 147: Bundle Request
            // Publish event for DataAvailabilityService to handle
            // Bundle requests are for bundle shards (audit shards)
            // Use AuditShardRequestReceived event which handles erasure root requests
            blockchain.publish(event: RuntimeEvents.AuditShardRequestReceived(
                erasureRoot: message.erasureRoot,
                shardIndex: 0 // Not applicable for full bundle request
            ))

            // Wait for response
            // Note: Currently returning empty response as the actual response
            // will be handled via the network layer by DataAvailabilityService
            logger.debug("CE 147 bundle request received for erasure root: \(message.erasureRoot.toHexString())")
            return []
        case let .stateRequest(message):
            blockchain
                .publish(
                    event: RuntimeEvents
                        .StateRequestReceived(
                            headerHash: message.headerHash,
                            startKey: message.startKey,
                            endKey: message.endKey,
                            maxSize: message.maxSize
                        )
                )
            // TODO: waitfor StateRequestReceivedResponse
            // let resp = try await blockchain.waitFor(RuntimeEvents.StateRequestReceivedResponse.self) { event in
            //
            // }
            return []
        case let .safroleTicket1(message):
            blockchain.publish(event: RuntimeEvents.SafroleTicketsReceived(
                items: [
                    ExtrinsicTickets.TicketItem(
                        attempt: message.attempt,
                        signature: message.proof
                    ),
                ]
            ))
            // TODO: rebroadcast to other peers after some time
            return []
        case let .safroleTicket2(message):
            blockchain.publish(event: RuntimeEvents.SafroleTicketsReceived(
                items: [
                    ExtrinsicTickets.TicketItem(
                        attempt: message.attempt,
                        signature: message.proof
                    ),
                ]
            ))
            return []
        case let .workPackageSubmission(message):
            blockchain
                .publish(
                    event: RuntimeEvents
                        .WorkPackagesReceived(
                            coreIndex: message.coreIndex,
                            workPackage: message.workPackage.asRef(),
                            extrinsics: message.extrinsics
                        )
                )
            return []
        case let .workPackageSharing(message):
            let hash = message.bundle.hash()
            blockchain
                .publish(
                    event: RuntimeEvents
                        .WorkPackageBundleReceived(
                            coreIndex: message.coreIndex,
                            bundle: message.bundle,
                            segmentsRootMappings: message.segmentsRootMappings
                        )
                )
            let resp = try await blockchain.waitFor(RuntimeEvents.WorkPackageBundleReceivedResponse.self) { event in
                hash == event.workBundleHash
            }
            let (workReportHash, signature) = try resp.result.get()
            return try [JamEncoder.encode(workReportHash, signature)]
        case let .workReportDistribution(message):
            let hash = message.workReport.hash()
            blockchain
                .publish(
                    event: RuntimeEvents
                        .WorkReportReceived(
                            workReport: message.workReport,
                            slot: message.slot,
                            signatures: message.signatures
                        )
                )

            let resp = try await blockchain.waitFor(RuntimeEvents.WorkReportReceivedResponse.self) { event in
                hash == event.workReportHash
            }
            _ = try resp.result.get()
            return []
        case let .workReportRequest(message):
            let workReportRef = try await blockchain.dataProvider.getGuaranteedWorkReport(hash: message.workReportHash)
            if let workReport = workReportRef {
                return try [JamEncoder.encode(workReport.value)]
            }
            return []
        case let .shardDistribution(message):
            let receivedEvent = RuntimeEvents.ShardDistributionReceived(erasureRoot: message.erasureRoot, shardIndex: message.shardIndex)
            let requestId = try receivedEvent.generateRequestId()

            blockchain.publish(event: receivedEvent)

            let resp = try await blockchain.waitFor(RuntimeEvents.ShardDistributionReceivedResponse.self) { event in
                requestId == event.requestId
            }
            let (bundleShard, segmentShards, justification) = try resp.result.get()
            return try [JamEncoder.encode(bundleShard, segmentShards, justification)]
        case let .auditShardRequest(message):
            blockchain
                .publish(event: RuntimeEvents.AuditShardRequestReceived(erasureRoot: message.erasureRoot, shardIndex: message.shardIndex))
            // TODO: waitfor AuditShardRequestReceivedResponse
            // let resp = try await blockchain.waitFor(RuntimeEvents.AuditShardRequestReceivedResponse.self) { event in
            //
            // }
            return []
        case let .segmentShardRequest1(message):
            blockchain
                .publish(
                    event: RuntimeEvents
                        .SegmentShardRequestReceived(
                            erasureRoot: message.erasureRoot,
                            shardIndex: message.shardIndex,
                            segmentIndices: message.segmentIndices
                        )
                )
            // TODO: waitfor AuditShardRequestReceivedResponse
            // let resp = try await blockchain.waitFor(RuntimeEvents.AuditShardRequestReceivedResponse.self) { event in
            //
            // }
            return []
        case let .segmentShardRequest2(message):
            blockchain
                .publish(
                    event: RuntimeEvents
                        .SegmentShardRequestReceived(
                            erasureRoot: message.erasureRoot,
                            shardIndex: message.shardIndex,
                            segmentIndices: message.segmentIndices
                        )
                )
            // TODO: waitfor AuditShardRequestReceivedResponse
            return []
        case let .assuranceDistribution(message):
            blockchain
                .publish(
                    event: RuntimeEvents
                        .AssuranceDistributionReceived(
                            headerHash: message.headerHash,
                            bitfield: message.bitfield,
                            signature: message.signature
                        )
                )
            return []
        case let .preimageAnnouncement(message):
            blockchain
                .publish(
                    event: RuntimeEvents
                        .PreimageAnnouncementReceived(
                            serviceID: message.serviceID,
                            hash: message.hash,
                            preimageLength: message.preimageLength
                        )
                )
            return []
        case let .preimageRequest(message):
            blockchain.publish(event: RuntimeEvents.PreimageRequestReceived(hash: message.hash))
            // TODO: waitfor PreimageRequestReceivedResponse
            return []
        case let .judgementPublication(message):
            blockchain
                .publish(
                    event: RuntimeEvents
                        .JudgementPublicationReceived(
                            epochIndex: message.epochIndex,
                            validatorIndex: message.validatorIndex,
                            validity: message.validity,
                            workReportHash: message.workReportHash,
                            signature: message.signature
                        )
                )
            return []
        case let .auditAnnouncement(message):
            blockchain
                .publish(
                    event: RuntimeEvents
                        .AuditAnnouncementReceived(
                            headerHash: message.headerHash,
                            tranche: message.tranche,
                            announcement: message.announcement,
                            evidence: message.evidence
                        )
                )
            return []
        case let .segmentRequest(message):
            // CE 148: Segment Request
            // Publish event for DataAvailabilityService to handle
            // SegmentShardRequestReceived expects erasureRoot, shardIndex, and segmentIndices
            // For CE 148, we use erasureRoot as segmentsRoot and shardIndex as 0 (not applicable)
            for request in message.requests {
                blockchain.publish(event: RuntimeEvents.SegmentShardRequestReceived(
                    erasureRoot: request.segmentsRoot,
                    shardIndex: 0, // Not applicable for segment requests
                    segmentIndices: request.segmentIndices
                ))
            }

            // Note: Currently returning empty response as the actual response
            // will be handled via the network layer by DataAvailabilityService
            logger.debug("CE 148 segment request received for \(message.requests.count) segment roots")
            return []
        case let .workPackageBundleSubmission(message):
            // TODO: Implement CE work package bundle submission handling
            return []
        }
    }

    func handle(connection: some ConnectionInfoProtocol, upMessage: UPMessage) async throws {
        switch upMessage {
        case let .blockAnnouncementHandshake(message):
            logger.trace("received block announcement handshake: \(message)")
            try await peerManager.addPeer(
                id: PeerId(publicKey: connection.publicKey.unwrap(), address: connection.remoteAddress),
                handshake: message
            )
        case let .blockAnnouncement(message):
            logger.trace("received block announcement: \(message)")
            try await peerManager.updatePeer(
                id: PeerId(publicKey: connection.publicKey.unwrap(), address: connection.remoteAddress),
                message: message
            )
        }
    }

    func handle(
        connection _: some ConnectionInfoProtocol, stream: some StreamProtocol<UPMessage>, kind: UniquePresistentStreamKind
    ) async throws {
        switch kind {
        case .blockAnnouncement:
            // send handshake message
            let finalized = await blockchain.dataProvider.finalizedHead
            let heads = try await blockchain.dataProvider.getHeads()
            var headsWithTimeslot: [HashAndSlot] = []
            for head in heads {
                try await headsWithTimeslot.append(HashAndSlot(
                    hash: head,
                    timeslot: blockchain.dataProvider.getHeader(hash: head).value.timeslot
                ))
            }

            let handshake = BlockAnnouncementHandshake(
                finalized: HashAndSlot(hash: finalized.hash, timeslot: finalized.timeslot),
                heads: headsWithTimeslot
            )

            try await stream.send(message: .blockAnnouncementHandshake(handshake))
        }
    }
}
