import Blockchain
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
    func testWorkPackagesReceived() async throws {
        // Create dummy work packages
        let workPackage = WorkPackage.dummy(config: services.config).asRef()

        // Publish WorkPackagesReceived event
        await services.blockchain
            .publish(event: RuntimeEvents.WorkPackagesReceived(coreIndex: 0, workPackage: workPackage, extrinsics: []))

        // Wait for event processing
        await storeMiddleware.wait()

        // Verify network calls
        #expect(
            network.contain(calls: [
                .init(function: "connect", parameters: ["address": devPeers.first!, "role": PeerRole.validator]),
                .init(function: "sendToPeer", parameters: [
                    "message": CERequest.workPackageSubmission(
                        WorkPackageMessage(coreIndex: 0, workPackage: workPackage.value, extrinsics: [])
                    ),
                ]),
            ])
        )
    }

    @Test
    func testWorkPackagesShare() async throws {
        // Create dummy work packages
        let workPackage = WorkPackage.dummy(config: services.config).asRef()
        let bundle = WorkPackageBundle(
            workPackage: workPackage.value,
            extrinsic: [],
            importSegments: [],
            justifications: []
        )
        // Publish WorkPackagesShare event
        await services.blockchain
            .publish(event: RuntimeEvents.WorkPackageBundleShare(coreIndex: 0, bundle: bundle, segmentsRootMappings: []))

        // Wait for event processing
        await storeMiddleware.wait()

        // Verify network calls
        #expect(
            network.contain(calls: [
                .init(function: "connect", parameters: ["address": devPeers.first!, "role": PeerRole.validator]),
                .init(function: "sendToPeer", parameters: [
                    "message": CERequest.workPackageSharing(
                        WorkPackageShareMessage(coreIndex: 0, bundle: bundle, segmentsRootMappings: [])
                    ),
                ]),
            ])
        )
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
                .init(function: "connect", parameters: ["address": devPeers.first!, "role": PeerRole.validator]),
                .init(function: "broadcast", parameters: [
                    "kind": UniquePresistentStreamKind.blockAnnouncement,
                    "message": UPMessage.blockAnnouncementHandshake(BlockAnnouncementHandshake(
                        finalized: HashAndSlot(hash: block.header.parentHash, timeslot: 0),
                        heads: [HashAndSlot(hash: block.hash, timeslot: block.header.timeslot)]
                    )),
                ]),
            ])
        )
    }
}
