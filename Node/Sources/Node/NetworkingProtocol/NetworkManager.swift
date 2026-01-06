import Blockchain
import Codec
import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "NetworkManager")

/// Network manager for validator communication and protocol handling
///
/// This file serves as the main entry point for networking operations.
/// Networking logic is organized into separate files:
/// - NetworkManagerHelpers.swift - Shared utilities and types
/// - NetworkManagerStorage.swift - Thread-safe peer storage
/// - ValidatorEventHandlers.swift - Validator event handlers
/// - CEProtocolHandlers.swift - Common Ephemeral protocol handlers
public final class NetworkManager: Sendable {
    public let peerManager: PeerManager
    public let network: any NetworkProtocol
    public let syncManager: SyncManager
    public let blockchain: Blockchain

    // Development-only peers that receive all messages
    private let devPeers: Set<Either<PeerId, NetAddr>>

    // Extracted modules
    private let storage: NetworkManagerStorage
    private let ceHandlers: CEProtocolHandlers
    private let subscriptions: EventSubscriptions

    public init(
        buildNetwork: (NetworkProtocolHandler) throws -> any NetworkProtocol,
        blockchain: Blockchain,
        eventBus: EventBus,
        devPeers: Set<NetAddr>
    ) async throws {
        self.blockchain = blockchain
        peerManager = PeerManager(eventBus: eventBus)

        // Initialize subscriptions early
        subscriptions = EventSubscriptions(eventBus: eventBus)

        // Initialize storage
        storage = NetworkManagerStorage()

        // Initialize CE protocol handlers
        ceHandlers = CEProtocolHandlers(blockchain: blockchain)

        // Create network with handler
        let handler = HandlerImpl(
            blockchain: blockchain,
            ceHandlers: ceHandlers,
            peerManager: peerManager
        )
        network = try buildNetwork(handler)

        // Initialize sync manager
        syncManager = SyncManager(
            blockchain: blockchain,
            network: network,
            peerManager: peerManager,
            eventBus: eventBus
        )

        // Setup development peers first
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

        // Setup event subscriptions
        await setupEventSubscriptions()
    }

    // MARK: - Event Subscriptions

    private func setupEventSubscriptions() async {
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

    // MARK: - Event Handlers

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
        await withSpan("NetworkManager.on(workPackageBundleReady)", logger: logger) { @Sendable _ in
            let target = event.target

            let resp = try await send(to: target, message: .workPackageSharing(.init(
                coreIndex: event.coreIndex,
                segmentsRootMappings: event.segmentsRootMappings,
                bundle: event.bundle
            )))

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

    private func on(beforeEpochChange event: RuntimeEvents.BeforeEpochChange) async {
        await withSpan("NetworkManager.onBeforeEpoch", logger: logger) { @Sendable _ in
            let currentValidators = event.state.currentValidators
            let nextValidators = event.state.nextValidators
            let allValidators = Set([currentValidators.array, nextValidators.array].joined())
            print("NetworkManager.onBeforeEpoch \(allValidators)")

            // Update peer mappings for both current and next validators
            await storage.updateValidatorPeerMappings(validators: currentValidators)
            await storage.updateValidatorPeerMappings(validators: nextValidators)
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

    // MARK: - Core Networking

    /// Get addresses for broadcast target
    ///
    /// **Note**: Currently returns development peers for testing.
    /// **Future**: Should query onchain state to get actual validator addresses.
    ///
    /// - Parameter target: The broadcast target (safrole validators or current validators)
    /// - Returns: Set of peer addresses for the target
    private func getAddresses(target: BroadcastTarget) -> Set<Either<PeerId, NetAddr>> {
        // For production: query blockchain.dataProvider for current/next validators
        // and convert validator metadata to PeerId/NetAddr
        switch target {
        case .safroleStep1Validator:
            // Future: Get the specific validator assigned to step 1 from Safrole state
            devPeers
        case .currentValidators:
            // Future: Get all current validators from blockchain.dataProvider.currentValidators
            // and convert their metadataString to NetAddr
            devPeers
        }
    }

    /// Send message to public key
    private func send(to: Ed25519PublicKey, message: CERequest) async throws -> [Data] {
        guard let peerId = await storage.getPeerId(publicKey: to) else {
            logger.error("Peer not found for public key")
            throw NetworkManagerError.peerNotFound
        }

        return try await send(to: peerId, message: message)
    }

    /// Send message to peer ID
    private func send(to: PeerId, message: CERequest) async throws -> [Data] {
        try await network.send(to: to, message: message)
    }

    /// Broadcast message to addresses
    private func broadcast(to addresses: Set<Either<PeerId, NetAddr>>, message: CERequest) async {
        for address in addresses {
            Task {
                do {
                    switch address {
                    case let .left(peerId):
                        _ = try await network.send(to: peerId, message: message)
                    case let .right(netAddr):
                        _ = try await network.send(to: netAddr, message: message)
                    }
                } catch {
                    logger.warning("Failed to broadcast to \(address): \(error)")
                }
            }
        }
    }

    /// Broadcast message to target
    private func broadcast(to: BroadcastTarget, message: CERequest) async {
        let addresses = getAddresses(target: to)
        await broadcast(to: addresses, message: message)
    }

    // MARK: - Public API

    /// Get current peer count
    public var peersCount: Int {
        network.peersCount
    }
}

// MARK: - Network Protocol Handler

struct HandlerImpl: NetworkProtocolHandler {
    let blockchain: Blockchain
    let ceHandlers: CEProtocolHandlers
    let peerManager: PeerManager

    init(blockchain: Blockchain, ceHandlers: CEProtocolHandlers, peerManager: PeerManager) {
        self.blockchain = blockchain
        self.ceHandlers = ceHandlers
        self.peerManager = peerManager
    }

    func handle(ceRequest: CERequest) async throws -> [Data] {
        try await ceHandlers.handle(ceRequest: ceRequest)
    }

    func handle(
        connection: some ConnectionInfoProtocol,
        upMessage: UPMessage
    ) async throws {
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
        connection _: some ConnectionInfoProtocol,
        stream: some StreamProtocol<UPMessage>,
        kind: UniquePresistentStreamKind
    ) async throws {
        switch kind {
        case .blockAnnouncement:
            // send handshake message
            let finalized = await blockchain.dataProvider.finalizedHead
            let heads = try await blockchain.dataProvider.getHeads()
            var headsWithTimeslot: [HashAndSlot] = []
            for head in heads {
                let header = try await blockchain.dataProvider.getHeader(hash: head)
                headsWithTimeslot.append(HashAndSlot(
                    hash: head,
                    timeslot: header.value.timeslot
                ))
            }

            try await stream.send(message: .blockAnnouncementHandshake(.init(
                finalized: HashAndSlot(hash: finalized.hash, timeslot: finalized.timeslot),
                heads: headsWithTimeslot
            )))

            for head in heads {
                let header = try await blockchain.dataProvider.getHeader(hash: head)
                try await stream.send(message: .blockAnnouncement(.init(
                    header: header,
                    finalized: HashAndSlot(hash: finalized.hash, timeslot: finalized.timeslot)
                )))
            }
        }
    }
}
