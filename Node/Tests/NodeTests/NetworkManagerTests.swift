import Blockchain
import Codec
import Foundation
@testable import Node
import Testing
import Utils

struct NetworkManagerTests {
    let networkManager: NetworkManager
    let network: MockNetwork
    let services: BlockchainServices
    let storeMiddleware: StoreMiddleware
    let devPeers: Set<NetAddr> = [NetAddr(address: "127.0.0.1:5000")!]

    init() async throws {
        let services = await BlockchainServices()
        var network: MockNetwork!

        let networkManager = try await NetworkManager(
            buildNetwork: { handler in
                network = MockNetwork(handler: handler)
                return network
            },
            blockchain: services.blockchain,
            eventBus: services.eventBus,
            devPeers: devPeers
        )

        self.networkManager = networkManager
        self.network = network
        self.services = services
        storeMiddleware = services.storeMiddleware

        await services.publishOnBeforeEpochEvent()
        await storeMiddleware.wait() // ensure all events are processed including onBeforeEpoch
    }

    @Test
    func testSafroleTicketsGeneration() async throws {
        // Generate safole tickets
        let tickets = [ExtrinsicTickets.TicketItem(
            attempt: 0,
            signature: .init()
        )]

        let epochIndex = EpochIndex(0)

        let key = try DevKeyStore.getDevKey(seed: 0)

        await services.eventBus.publish(RuntimeEvents.SafroleTicketsGenerated(
            epochIndex: epochIndex,
            items: tickets.map { ticket in
                TicketItemAndOutput(
                    ticket: ticket,
                    output: Data32()
                )
            },
            publicKey: key.bandersnatch
        ))

        // Wait for event processing
        await storeMiddleware.wait()
        #expect(network.peerRole == .builder)
        #expect(network.peersCount == 0)
        #expect(network.networkKey == "mock_network_key")
        // Verify network calls
        #expect(
            network.contain(calls: [
                .init(function: "connect", parameters: ["address": devPeers.first!, "role": PeerRole.validator]),
                .init(function: "sendToPeer", parameters: [
                    "message": CERequest.safroleTicket1(SafroleTicketMessage(
                        epochIndex: epochIndex,
                        attempt: tickets[0].attempt,
                        proof: tickets[0].signature
                    )),
                ]),
            ])
        )
    }

    @Test
    func testWorkPackageBundleReady() async throws {
        let bundle = WorkPackageBundle.dummy(config: services.config)
        let key = try DevKeyStore.getDevKey(seed: 0)
        let segmentsRootMappings = [SegmentsRootMapping(workPackageHash: Data32(repeating: 1), segmentsRoot: Data32(repeating: 2))]
        let workReportHash = Data32(repeating: 2)
        let signature = Ed25519Signature(repeating: 3)
        let expectedResp = try JamEncoder.encode(workReportHash, signature)
        network.state.write { $0.simulatedResponseData = [expectedResp] }

        // Publish WorkPackagesReceived event
        await services.blockchain
            .publish(event: RuntimeEvents.WorkPackageBundleReady(
                target: key.ed25519.data,
                coreIndex: 1,
                bundle: bundle,
                segmentsRootMappings: segmentsRootMappings
            ))

        // Wait for event processing
        let events = await storeMiddleware.wait()

        // Verify network calls
        #expect(
            network.contain(calls: [
                .init(function: "connect", parameters: ["address": devPeers.first!, "role": PeerRole.validator]),
                .init(function: "sendToPeer", parameters: [
                    "peerId": PeerId(publicKey: key.ed25519.data.data, address: NetAddr(address: "127.0.0.1:5000")!),
                    "message": CERequest.workPackageSharing(.init(
                        coreIndex: 1,
                        segmentsRootMappings: segmentsRootMappings,
                        bundle: bundle
                    )),
                ]),
            ])
        )

        let event = events.first { $0 is RuntimeEvents.WorkPackageBundleRecivedReply } as! RuntimeEvents.WorkPackageBundleRecivedReply
        #expect(event.source == key.ed25519.data)
        #expect(event.workReportHash == workReportHash)
        #expect(event.signature == signature)
    }

    @Test
    func testBlockBroadcast() async throws {
        // Import a block
        let block = BlockRef.dummy(config: services.config, parent: services.genesisBlock)
        let state = StateRef.dummy(config: services.config, block: block)

        try await services.dataProvider.blockImported(block: block, state: state)

        await services.eventBus.publish(RuntimeEvents.BlockImported(
            block: block,
            state: state,
            parentState: services.genesisState
        ))

        // Wait for event processing
        await storeMiddleware.wait()

        // Verify network broadcast
        #expect(
            network.contain(calls: [
                .init(function: "broadcast", parameters: [
                    "kind": UniquePresistentStreamKind.blockAnnouncement,
                    "message": UPMessage.blockAnnouncement(.init(
                        header: block.header.asRef(),
                        finalized: HashAndSlot(hash: block.header.parentHash, timeslot: 0)
                    )),
                ]),
            ])
        )
    }
}
