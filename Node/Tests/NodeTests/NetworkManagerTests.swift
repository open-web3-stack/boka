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
            ]),
            "network calls: \(network.calls)"
        )

        let event = try #require(events.first { $0 is RuntimeEvents.WorkPackageBundleRecivedReply } as? RuntimeEvents
            .WorkPackageBundleRecivedReply)
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

    @Test
    func testPeersCount() async throws {
        // Configure simulated peers count
        let expectedPeersCount = 5
        network.state.write { $0.simulatedPeersCount = expectedPeersCount }

        // Verify peersCount property forwards to network implementation
        #expect(networkManager.peersCount == expectedPeersCount)
    }

    @Test
    func testHandleCERequest() async throws {
        // Setup mock data
        let blockRequest = BlockRequest(
            hash: services.genesisBlock.hash,
            direction: .descendingInclusive,
            maxBlocks: 10
        )

        // Test handling block request
        let response = try await network.handler.handle(ceRequest: .blockRequest(blockRequest))

        // Verify response
        let data = try #require(response.first)

        let decoder = JamDecoder(data: data, config: services.config)
        let block = try decoder.decode(BlockRef.self)

        // Verify decoded block matches genesis block
        #expect(block.hash == services.genesisBlock.hash)
    }

    @Test
    func testWorkPackagesSubmitted() async throws {
        // Create work package and extrinsics
        let workPackage = WorkPackageRef.dummy(config: services.config)
        let extrinsics = [Data(repeating: 5, count: 32)]
        let coreIndex: CoreIndex = 1

        // Publish WorkPackagesSubmitted event
        await services.eventBus.publish(RuntimeEvents.WorkPackagesSubmitted(
            coreIndex: coreIndex,
            workPackage: workPackage,
            extrinsics: extrinsics
        ))

        // Wait for event processing
        await storeMiddleware.wait()

        #expect(network.contain(calls: [
            .init(function: "sendToPeer", parameters: [
                "message": CERequest.workPackageSubmission(.init(
                    coreIndex: coreIndex,
                    workPackage: workPackage.value,
                    extrinsics: extrinsics
                )),
            ]),
        ]))
    }

    @Test
    func testProcessingBlockRequest() async throws {
        // Setup mock data
        let blockRequest = BlockRequest(
            hash: services.genesisBlock.hash,
            direction: .descendingInclusive,
            maxBlocks: 10
        )

        // Test handling block request
        let response = try await network.handler.handle(ceRequest: .blockRequest(blockRequest))

        // Verify response
        let data = try #require(response.first)

        let decoder = JamDecoder(data: data, config: services.config)
        let block = try decoder.decode(BlockRef.self)

        // Verify decoded block matches genesis block
        #expect(block.hash == services.genesisBlock.hash)
    }

    @Test
    func testHandleWorkPackageSubmission() async throws {
        // Create work package and extrinsics
        let workPackage = WorkPackageRef.dummy(config: services.config)
        let extrinsics = [Data(repeating: 5, count: 32)]
        let coreIndex: CoreIndex = 3

        // Handle WorkPackageSubmission message
        let submissionMessage = CERequest.workPackageSubmission(.init(
            coreIndex: coreIndex,
            workPackage: workPackage.value,
            extrinsics: extrinsics
        ))

        // Process the request
        _ = try await network.handler.handle(ceRequest: submissionMessage)

        // Wait for event processing and collect events
        let events = await storeMiddleware.wait()

        // Find the WorkPackagesReceived event
        let receivedEvent = events.first {
            if let event = $0 as? RuntimeEvents.WorkPackagesReceived {
                return event.coreIndex == coreIndex
            }
            return false
        } as? RuntimeEvents.WorkPackagesReceived

        // Verify the event was published with correct data
        let event = try #require(receivedEvent)
        #expect(event.coreIndex == coreIndex)
        #expect(event.workPackage.hash == workPackage.hash)
        #expect(event.extrinsics == extrinsics)
    }

    @Test
    func testPeerNotFoundWhenBroadcastingWorkPackageBundle() async throws {
        // In this test, we publish a WorkPackageBundleReady event
        // with a target that doesn't match any known peer (i.e., not the dev peer),
        // so the send call should fail with .peerNotFound internally.
        // We then verify that no WorkPackageBundleRecivedReply event is published.

        let randomKey = Ed25519PublicKey(repeating: 99)
        let bundle = WorkPackageBundle.dummy(config: services.config)
        let segmentsRootMappings = [SegmentsRootMapping(workPackageHash: Data32(), segmentsRoot: Data32())]

        // Publish the event
        await services.blockchain.publish(event: RuntimeEvents.WorkPackageBundleReady(
            target: randomKey,
            coreIndex: 123,
            bundle: bundle,
            segmentsRootMappings: segmentsRootMappings
        ))

        // Wait for async processing
        let events = await storeMiddleware.wait()
        let reply = events.first(where: { $0 is RuntimeEvents.WorkPackageBundleRecivedReply })

        // Ensure that no reply was published
        #expect(reply == nil)
    }

    @Test
    func testWorkPackageBundleReadyInvalidResponse() async throws {
        // Here, we configure the mock network to provide an empty response.
        // That should trigger the "WorkPackageSharing response is invalid" path,
        // preventing publication of a WorkPackageBundleRecivedReply event.

        network.state.write { $0.simulatedResponseData = [] }

        // Since the dev peer public key in the mock is all zeros,
        // we'll use Data32(repeating: 0) for the target to avoid a peerNotFound error.
        let target = Data32(repeating: 0)
        let bundle = WorkPackageBundle.dummy(config: services.config)
        let segmentsRootMappings = [SegmentsRootMapping(
            workPackageHash: Data32(),
            segmentsRoot: Data32()
        )]

        await services.blockchain.publish(event: RuntimeEvents.WorkPackageBundleReady(
            target: target,
            coreIndex: 321,
            bundle: bundle,
            segmentsRootMappings: segmentsRootMappings
        ))

        // Wait for async processing
        let events = await storeMiddleware.wait()
        let reply = events.first(where: { $0 is RuntimeEvents.WorkPackageBundleRecivedReply })

        // Verify no event was published
        #expect(reply == nil)
    }
}
