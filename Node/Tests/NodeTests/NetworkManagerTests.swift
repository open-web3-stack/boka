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
        await services.publishOnBeforeEpochEvent()
        network.state.write {
            $0.simulatedResponseData = [expectedResp]
            $0.simulatedPeerRole = .validator
        }
        // Publish WorkPackagesReceived event
        await services.blockchain
            .publish(event: RuntimeEvents.WorkPackageBundleReady(
                target: key.ed25519.data,
                coreIndex: 1,
                bundle: bundle,
                segmentsRootMappings: segmentsRootMappings
            ))
        try? await Task.sleep(for: .milliseconds(1000))

        // Wait for event processing
        let events = await storeMiddleware.wait()

        #expect(network.calls.count == 3)

        let event = events.first { $0 is RuntimeEvents.WorkPackageBundleReceivedReply } as? RuntimeEvents
            .WorkPackageBundleReceivedReply
        #expect(event?.source == key.ed25519.data)
        #expect(event?.workReportHash == workReportHash)
        #expect(event?.signature == signature)
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

        // Wait for event processing
        await storeMiddleware.wait()

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

        // Wait for event processing
        await storeMiddleware.wait()

        // Verify response
        let data = try #require(response.first)

        let decoder = JamDecoder(data: data, config: services.config)
        let block = try decoder.decode(BlockRef.self)

        // Verify decoded block matches genesis block
        #expect(block.hash == services.genesisBlock.hash)
    }

    @Test
    func testWorkPackageBundleReadyInvalidResponse() async throws {
        // Here, we configure the mock network to provide an empty response.
        // That should trigger the "WorkPackageSharing response is invalid" path,
        // preventing publication of a WorkPackageBundleReceivedReply event.

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
        let reply = events.first(where: { $0 is RuntimeEvents.WorkPackageBundleReceivedReply })

        // Verify no event was published
        #expect(reply == nil)
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
        // We then verify that no WorkPackageBundleReceivedReply event is published.

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
        let reply = events.first(where: { $0 is RuntimeEvents.WorkPackageBundleReceivedReply })

        // Ensure that no reply was published
        #expect(reply == nil)
    }

    @Test
    func testHandleWorkReportDistribution() async throws {
        let workReport = WorkReport.dummy(config: services.config)
        let slot: UInt32 = 123
        let signatures = [ValidatorSignature(validatorIndex: 0, signature: Ed25519Signature(repeating: 20))]

        let distributionMessage = CERequest.workReportDistribution(WorkReportDistributionMessage(
            workReport: workReport,
            slot: slot,
            signatures: signatures
        ))

        let message = try WorkReportDistributionMessage.decode(data: distributionMessage.encode(), config: services.config)
        #expect(slot == message.slot)

        _ = await services.dataAvailabilityService

        await #expect(throws: Error.self) {
            _ = try await network.handler.handle(ceRequest: distributionMessage)
        }
    }

    @Test
    func testHandleWorkReportRequest() async throws {
        let workReportHash = Data32(repeating: 1)

        let requestMessage = CERequest.workReportRequest(WorkReportRequestMessage(
            workReportHash: workReportHash
        ))

        let message = try WorkReportRequestMessage.decode(data: requestMessage.encode(), config: services.config)
        #expect(workReportHash == message.workReportHash)

        let data = try await network.handler.handle(ceRequest: requestMessage)

        await storeMiddleware.wait()
        #expect(data == [])
    }

    @Test
    func testHandleShardDistribution() async throws {
        let erasureRoot = Data32(repeating: 1)
        let shardIndex: UInt32 = 2

        let distributionMessage = CERequest.shardDistribution(ShardDistributionMessage(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        ))

        let message = try ShardDistributionMessage.decode(data: distributionMessage.encode(), config: services.config)
        #expect(shardIndex == message.shardIndex)

        _ = try await network.handler.handle(ceRequest: distributionMessage)

        let events = await storeMiddleware.wait()

        let receivedEvent = events.first {
            if let event = $0 as? RuntimeEvents.ShardDistributionReceived {
                return event.erasureRoot == erasureRoot && event.shardIndex == shardIndex
            }
            return false
        } as? RuntimeEvents.ShardDistributionReceived

        let event = try #require(receivedEvent)
        #expect(event.erasureRoot == erasureRoot)
        #expect(event.shardIndex == shardIndex)
    }

    @Test
    func testHandleAuditShardRequest() async throws {
        let testErasureRoot = Data32(repeating: 1)
        let testShardIndex: UInt32 = 2
        let testBundleShard = Data([0x01, 0x02, 0x03])
        let testJustification = Justification.singleHash(Data32())
        let testError = NSError(domain: "test", code: 404)

        let requestMessage = CERequest.auditShardRequest(AuditShardRequestMessage(
            erasureRoot: testErasureRoot,
            shardIndex: testShardIndex
        ))

        let message = try AuditShardRequestMessage.decode(data: requestMessage.encode(), config: services.config)
        #expect(testShardIndex == message.shardIndex)

        _ = try await network.handler.handle(ceRequest: requestMessage)

        let events = await storeMiddleware.wait()
        var receivedCount = 0
        var generatedRequestId = Data32()

        for event in events {
            if let requestEvent = event as? RuntimeEvents.AuditShardRequestReceived {
                #expect(requestEvent.erasureRoot == testErasureRoot)
                #expect(requestEvent.shardIndex == testShardIndex)
                generatedRequestId = try requestEvent.generateRequestId()
                receivedCount += 1
            }
        }

        #expect(receivedCount == 1)

        let successResponse = RuntimeEvents.AuditShardRequestReceivedResponse(
            requestId: generatedRequestId,
            erasureRoot: testErasureRoot,
            shardIndex: testShardIndex,
            bundleShard: testBundleShard,
            justification: testJustification
        )

        #expect(successResponse.requestId == generatedRequestId)
        #expect(try successResponse.result.get().erasureRoot == testErasureRoot)
        #expect(try successResponse.result.get().shardIndex == testShardIndex)
        #expect(try successResponse.result.get().bundleShard == testBundleShard)
        #expect(try successResponse.result.get().justification == testJustification)

        let failureResponse = RuntimeEvents.AuditShardRequestReceivedResponse(
            requestId: generatedRequestId,
            error: testError
        )

        #expect(failureResponse.requestId == generatedRequestId)
        #expect(throws: NSError.self) {
            try failureResponse.result.get()
        }
    }

    @Test
    func testHandleSegmentShardRequest() async throws {
        let testErasureRoot = Data32(repeating: 1)
        let testShardIndex: UInt32 = 2
        let testSegmentIndices: [UInt16] = [1, 2, 3]
        let testSegments = [SegmentShard(shard: Data12(repeating: 0), justification: nil)]
        let testError = NSError(domain: "test", code: 404)

        let requestMessage = try SegmentShardRequestMessage(
            erasureRoot: testErasureRoot,
            shardIndex: testShardIndex,
            segmentIndices: testSegmentIndices
        )

        let requestMessage1 = CERequest.segmentShardRequest1(requestMessage)
        let requestMessage2 = CERequest.segmentShardRequest2(requestMessage)

        let message1 = try SegmentShardRequestMessage.decode(data: requestMessage1.encode(), config: services.config)
        #expect(testShardIndex == message1.shardIndex)
        let message2 = try SegmentShardRequestMessage.decode(data: requestMessage2.encode(), config: services.config)
        #expect(testShardIndex == message2.shardIndex)

        _ = try await network.handler.handle(ceRequest: requestMessage1)
        _ = try await network.handler.handle(ceRequest: requestMessage2)

        let events = await storeMiddleware.wait()
        var receivedCount = 0
        var generatedRequestId = Data32()

        for event in events {
            if let requestEvent = event as? RuntimeEvents.SegmentShardRequestReceived {
                #expect(requestEvent.erasureRoot == testErasureRoot)
                #expect(requestEvent.shardIndex == testShardIndex)
                #expect(requestEvent.segmentIndices == testSegmentIndices)
                generatedRequestId = try requestEvent.generateRequestId()
                receivedCount += 1
            }
        }

        #expect(receivedCount == 2)

        let successResponse = RuntimeEvents.SegmentShardRequestReceivedResponse(
            requestId: generatedRequestId,
            segments: testSegments
        )
        #expect(successResponse.requestId == generatedRequestId)
        #expect(try successResponse.result.get().count == testSegments.count)

        let failureResponse = RuntimeEvents.SegmentShardRequestReceivedResponse(
            requestId: generatedRequestId,
            error: testError
        )
        #expect(failureResponse.requestId == generatedRequestId)
        #expect(throws: NSError.self) {
            try failureResponse.result.get()
        }
    }

    @Test
    func testHandleAssuranceDistributionMessage() async throws {
        let testHeaderHash = Data32(repeating: 1)
        let testBitfield = try ConfigSizeBitString<ProtocolConfig.TotalNumberOfCores>(
            config: services.config,
            data: Data(repeating: 0, count: (services.config.value.totalNumberOfCores + 7) >> 3)
        )

        let testSignature = Ed25519Signature(repeating: 2)

        let requestMessage = CERequest.assuranceDistribution(AssuranceDistributionMessage(
            headerHash: testHeaderHash,
            bitfield: testBitfield,
            signature: testSignature
        ))

        let message = try AssuranceDistributionMessage.decode(data: requestMessage.encode(), config: services.config)
        #expect(testBitfield == message.bitfield)

        _ = try await network.handler.handle(ceRequest: requestMessage)

        let events = await storeMiddleware.wait()

        for event in events {
            if let receivedEvent = event as? RuntimeEvents.AssuranceDistributionReceived {
                #expect(receivedEvent.headerHash == testHeaderHash)
                #expect(receivedEvent.bitfield == testBitfield)
                #expect(receivedEvent.signature == testSignature)
            }
        }
    }

    @Test
    func testHandlePreimageAnnouncementMessage() async throws {
        let testServiceID: UInt32 = 42
        let testPreimageHash = Data32(repeating: 1)
        let testPreimageLength: UInt32 = 256

        let requestMessage = CERequest.preimageAnnouncement(PreimageAnnouncementMessage(
            serviceID: testServiceID,
            hash: testPreimageHash,
            preimageLength: testPreimageLength
        ))

        let message = try PreimageAnnouncementMessage.decode(data: requestMessage.encode(), config: services.config)
        #expect(testPreimageHash == message.hash)

        _ = try await network.handler.handle(ceRequest: requestMessage)

        let events = await storeMiddleware.wait()

        for event in events {
            if let receivedEvent = event as? RuntimeEvents.PreimageAnnouncementReceived {
                #expect(receivedEvent.serviceID == testServiceID)
                #expect(receivedEvent.hash == testPreimageHash)
                #expect(receivedEvent.preimageLength == testPreimageLength)
            }
        }
    }

    @Test
    func testHandlePreimageRequestMessage() async throws {
        let testPreimageHash = Data32(repeating: 1)
        let testPreimage = Data([0x01, 0x02, 0x03])
        let testError = NSError(domain: "test", code: 404)

        let requestMessage = CERequest.preimageRequest(PreimageRequestMessage(
            hash: testPreimageHash
        ))

        let message = try PreimageRequestMessage.decode(data: requestMessage.encode(), config: services.config)
        #expect(testPreimageHash == message.hash)

        _ = try await network.handler.handle(ceRequest: requestMessage)

        let events = await storeMiddleware.wait()
        var receivedCount = 0

        for event in events {
            if let receivedEvent = event as? RuntimeEvents.PreimageRequestReceived {
                #expect(receivedEvent.hash == testPreimageHash)
                receivedCount += 1
            }
        }

        #expect(receivedCount == 1)

        let successResponse = RuntimeEvents.PreimageRequestReceivedResponse(
            hash: testPreimageHash,
            preimage: testPreimage
        )
        #expect(successResponse.hash == testPreimageHash)
        #expect(try successResponse.result.get() == testPreimage)

        let failureResponse = RuntimeEvents.PreimageRequestReceivedResponse(
            hash: testPreimageHash,
            error: testError
        )
        #expect(failureResponse.hash == testPreimageHash)
        #expect(throws: NSError.self) {
            try failureResponse.result.get()
        }
    }

    @Test
    func testHandleJudgementPublication() async throws {
        let testEpochIndex: EpochIndex = 123
        let testValidatorIndex: ValidatorIndex = 5
        let testValidity: UInt8 = 1 // Valid
        let testWorkReportHash = Data32(repeating: 0xAA)
        let testSignature = Ed25519Signature(repeating: 0xBB)

        let requestMessage = CERequest.judgementPublication(JudgementPublicationMessage(
            epochIndex: testEpochIndex,
            validatorIndex: testValidatorIndex,
            validity: testValidity,
            workReportHash: testWorkReportHash,
            signature: testSignature
        ))

        let message = try JudgementPublicationMessage.decode(data: requestMessage.encode(), config: services.config)
        #expect(testEpochIndex == message.epochIndex)

        _ = try await network.handler.handle(ceRequest: requestMessage)

        let events = await storeMiddleware.wait()
        var receivedCount = 0

        for event in events {
            if let receivedEvent = event as? RuntimeEvents.JudgementPublicationReceived {
                #expect(receivedEvent.epochIndex == testEpochIndex)
                #expect(receivedEvent.validatorIndex == testValidatorIndex)
                #expect(receivedEvent.validity == testValidity)
                #expect(receivedEvent.workReportHash == testWorkReportHash)
                #expect(receivedEvent.signature == testSignature)
                receivedCount += 1
            }
        }

        #expect(receivedCount == 1)
    }

    @Test
    func testHandleFirstTrancheAnnouncement() async throws {
        let testHeaderHash = Data32(repeating: 0xAA)
        let testAnnouncement = Announcement(
            workReports: [
                .init(coreIndex: 1, workReportHash: Data32(repeating: 0xBB)),
            ],
            signature: Ed25519Signature(repeating: 0xCC)
        )

        let testEvidence = Evidence.firstTranche(Data96(repeating: 0xDD))

        let requestMessage = CERequest.auditAnnouncement(AuditAnnouncementMessage(
            headerHash: testHeaderHash,
            tranche: 0,
            announcement: testAnnouncement,
            evidence: testEvidence
        ))

        let message = try AuditAnnouncementMessage.decode(data: requestMessage.encode(), config: services.config)
        #expect(testAnnouncement == message.announcement)

        _ = try await network.handler.handle(ceRequest: .auditAnnouncement(message))

        let events = await storeMiddleware.wait()
        var receivedCount = 0

        for event in events {
            if let receivedEvent = event as? RuntimeEvents.AuditAnnouncementReceived {
                #expect(receivedEvent.headerHash == testHeaderHash)
                #expect(receivedEvent.tranche == 0)
                #expect(receivedEvent.announcement.workReports.count == 1)
                #expect(receivedEvent.evidence == testEvidence)
                receivedCount += 1
            }
        }
        #expect(receivedCount == 1)
    }

    @Test
    func testHandleSubsequentTrancheAnnouncement() async throws {
        let previousAnnouncement = Announcement(
            workReports: [
                .init(coreIndex: 1, workReportHash: Data32(repeating: 0x55)),
            ],
            signature: Ed25519Signature(repeating: 0x66)
        )

        let testNoShow = Evidence.NoShow(
            validatorIndex: 1,
            previousAnnouncement: previousAnnouncement
        )

        let testEvidence = Evidence.subsequentTranche([
            .init(
                bandersnatchSig: Data96(repeating: 0xEE),
                noShows: [testNoShow]
            ),
        ])

        let message = AuditAnnouncementMessage(
            headerHash: Data32(repeating: 0xFF),
            tranche: 1,
            announcement: Announcement(
                workReports: [
                    .init(coreIndex: 2, workReportHash: Data32(repeating: 0x11)),
                ],
                signature: Ed25519Signature(repeating: 0x22)
            ),
            evidence: testEvidence
        )

        _ = try await network.handler.handle(ceRequest: .auditAnnouncement(message))
        let events = await storeMiddleware.wait()

        var eventMatched = false
        for event in events {
            if let receivedEvent = event as? RuntimeEvents.AuditAnnouncementReceived {
                #expect(receivedEvent.tranche == 1)
                if case let .subsequentTranche(evidences) = receivedEvent.evidence {
                    #expect(evidences[0].noShows[0].previousAnnouncement.workReports[0].coreIndex == 1)
                }
                eventMatched = true
            }
        }
        #expect(eventMatched)
    }

    @Test
    func testHandleStateRequest() async throws {
        let testHeaderHash = Data32(repeating: 0x11)
        let testStartKey = Data31(repeating: 0x22)
        let testEndKey = Data31(repeating: 0x33)
        let testMaxSize: UInt32 = 2048

        let requestMessage = CERequest.stateRequest(StateRequest(
            headerHash: testHeaderHash,
            startKey: testStartKey,
            endKey: testEndKey,
            maxSize: testMaxSize
        ))

        let message = try StateRequest.decode(data: requestMessage.encode(), config: services.config)
        #expect(testHeaderHash == message.headerHash)

        _ = try await network.handler.handle(ceRequest: requestMessage)

        let events = await storeMiddleware.wait()
        var receivedCount = 0
        var generateRequestId = Data32()
        for event in events {
            if let receivedEvent = event as? RuntimeEvents.StateRequestReceived {
                #expect(receivedEvent.headerHash == testHeaderHash)
                #expect(receivedEvent.startKey == testStartKey)
                #expect(receivedEvent.endKey == testEndKey)
                #expect(receivedEvent.maxSize == testMaxSize)
                generateRequestId = try receivedEvent.generateRequestId()
                receivedCount += 1
            }
        }

        #expect(receivedCount == 1)
        let testNodes = [BoundaryNode]()
        let testKVPairs = [(key: Data31(), value: Data())]

        let response = RuntimeEvents.StateRequestReceivedResponse(
            requestId: generateRequestId,
            headerHash: testHeaderHash,
            boundaryNodes: testNodes,
            keyValuePairs: testKVPairs
        )
        #expect(response.requestId == generateRequestId)
        #expect(try response.result.get().headerHash == testHeaderHash)
        let responseFail = RuntimeEvents.StateRequestReceivedResponse(
            requestId: generateRequestId,
            error: NSError(domain: "test", code: 1)
        )
        #expect(throws: NSError.self) {
            try responseFail.result.get()
        }
    }
}
