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

public final class NetworkManager: Sendable {
    public let peerManager: PeerManager
    public let network: any NetworkProtocol
    public let syncManager: SyncManager
    public let blockchain: Blockchain
    private let subscriptions: EventSubscriptions

    // This is for development only
    // Those peers will receive all the messages regardless the target
    private let devPeers: Set<Either<PeerId, NetAddr>>

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

    private func send(to: PeerId, message: CERequest) async throws -> Data {
        try await network.send(to: to, message: message)
    }

    private func broadcast(
        to: BroadcastTarget,
        message: CERequest,
        responseHandler: @Sendable @escaping (Result<Data, Error>) async -> Void
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

    public var peersCount: Int {
        network.peersCount
    }
}

struct HandlerImpl: NetworkProtocolHandler {
    let blockchain: Blockchain
    let peerManager: PeerManager

    func handle(ceRequest: CERequest) async throws -> [any Encodable] {
        logger.trace("handling request", metadata: ["request": "\(ceRequest)"])
        switch ceRequest {
        case let .blockRequest(message):
            let dataProvider = blockchain.dataProvider
            let count = min(MAX_BLOCKS_PER_REQUEST, message.maxBlocks)
            var resp = [BlockRef]()
            resp.reserveCapacity(Int(count))
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
                            resp.append(block)
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
                    resp.append(block)
                    if hash == dataProvider.genesisBlockHash {
                        break
                    }
                    hash = block.header.parentHash
                }
            }
            return resp
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
            blockchain
                .publish(
                    event: RuntimeEvents
                        .WorkPackageBundleShare(
                            coreIndex: message.coreIndex,
                            bundle: message.bundle,
                            segmentsRootMappings: message.segmentsRootMappings
                        )
                )
            return []
        case let .workReportDistrubution(message):
            blockchain
                .publish(
                    event: RuntimeEvents
                        .GuranteedWorkReport(
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
