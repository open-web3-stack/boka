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

//            await subscriptions.subscribe(
//                RuntimeEvents.WorkReportReceived.self,
//                id: "NetworkManager.WorkReportReceived"
//            ) { [weak self] event in
//                await self?.on(workReportDistrubution: event)
//            }
//
//            await subscriptions.subscribe(
//                RuntimeEvents.SafroleTicketsReceived.self,
//                id: "NetworkManager.SafroleTicket1"
//            ) { [weak self] event in
//                await self?.on(safroleTicket1: event)
//            }
//
//            await subscriptions.subscribe(
//                RuntimeEvents.SafroleTicketsReceived.self,
//                id: "NetworkManager.SafroleTicket2"
//            ) { [weak self] event in
//                await self?.on(safroleTicket2: event)
//            }
//
//            await subscriptions.subscribe(
//                RuntimeEvents.WorkPackagesReceived.self,
//                id: "NetworkManager.WorkPackageSubmission"
//            ) { [weak self] event in
//                await self?.on(workPackageSubmission: event)
//            }
//
//            await subscriptions.subscribe(
//                RuntimeEvents.WorkPackageBundleRecived.self,
//                id: "NetworkManager.WorkPackageSharing"
//            ) { [weak self] event in
//                await self?.on(workPackageSharing: event)
//            }
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

//    private func on(workReportDistrubution event: RuntimeEvents.WorkReportReceived) async {
//        logger.trace("sending work report distribution", metadata: ["slot": "\(event.slot)"])
//        await broadcast(
//            to: .currentValidators,
//            message: .workReportDistrubution(.init(
//                workReport: event.workReport,
//                slot: event.slot,
//                signatures: event.signatures
//            ))
//        )
//    }
//
//
//    private func on(safroleTicket1 event: RuntimeEvents.SafroleTicketsReceived) async {
//        logger.trace("sending safrole ticket 1", metadata: ["attempt": "\(event.items.first?.attempt ?? 0)"])
//        for ticket in event.items {
//            await broadcast(
//                to: .safroleStep1Validator,
//                message: .safroleTicket1(.init(
//                    epochIndex: 0,
//                    attempt: ticket.attempt,
//                    proof: ticket.signature
//                ))
//            )
//        }
//    }
//
//    private func on(safroleTicket2 event: RuntimeEvents.SafroleTicketsReceived) async {
//        logger.trace("sending safrole ticket 2", metadata: ["attempt": "\(event.items.first?.attempt ?? 0)"])
//        for ticket in event.items {
//            await broadcast(
//                to: .safroleStep1Validator,
//                message: .safroleTicket2(.init(
//                    epochIndex: 0,
//                    attempt: ticket.attempt,
//                    proof: ticket.signature
//                ))
//            )
//        }
//    }
//
//    private func on(workPackageSubmission event: RuntimeEvents.WorkPackagesReceived) async {
//        logger.trace("sending work package submission", metadata: ["coreIndex": "\(event.coreIndex)"])
//        await broadcast(
//            to: .currentValidators,
//            message: .workPackageSubmission(.init(
//                coreIndex: event.coreIndex,
//                workPackage: event.workPackage.value,
//                extrinsics: event.extrinsics
//            ))
//        )
//    }
//
//    private func on(workPackageSharing event: RuntimeEvents.WorkPackageBundleRecived) async {
//        logger.trace("sending work package sharing", metadata: ["coreIndex": "\(event.coreIndex)"])
//        await broadcast(
//            to: .currentValidators,
//            message: .workPackageSharing(.init(
//                coreIndex: event.coreIndex,
//                segmentsRootMappings: event.segmentsRootMappings,
//                bundle: event.bundle
//            ))
//        )
//    }

    private func on(safroleTicketsGenerated event: RuntimeEvents.SafroleTicketsGenerated) async {
        logger.trace("sending tickets", metadata: ["epochIndex": "\(event.epochIndex)"])
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

            blockchain.publish(event: RuntimeEvents.WorkPackageBundleRecivedReply(
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
                        .WorkPackageBundleRecived(
                            coreIndex: message.coreIndex,
                            bundle: message.bundle,
                            segmentsRootMappings: message.segmentsRootMappings
                        )
                )
            let resp = try await blockchain.waitFor(RuntimeEvents.WorkPackageBundleRecivedResponse.self) { event in
                hash == event.workBundleHash
            }
            let (workReportHash, signature) = try resp.result.get()
            return try [JamEncoder.encode(workReportHash, signature)]
        case let .workReportDistrubution(message):
            blockchain
                .publish(
                    event: RuntimeEvents
                        .WorkReportReceived(
                            workReport: message.workReport,
                            slot: message.slot,
                            signatures: message.signatures
                        )
                )
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
