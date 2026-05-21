@testable import Blockchain
import Codec
import Foundation
import Testing
import Utils

private enum RuntimeEventsTestError: Error {
    case sample
}

struct RuntimeEventsTests {
    @Test
    func requestIdsHashTheEncodedRequestFields() throws {
        let stateRequest = RuntimeEvents.StateRequestReceived(
            headerHash: data32(1),
            startKey: data31(2),
            endKey: data31(3),
            maxSize: 128,
        )
        #expect(
            try stateRequest.generateRequestId() ==
                JamEncoder.encode(data32(1), data31(2), data31(3), UInt32(128)).blake2b256hash(),
        )

        let shardDistribution = RuntimeEvents.ShardDistributionReceived(erasureRoot: data32(4), shardIndex: 7)
        #expect(
            try shardDistribution.generateRequestId() ==
                JamEncoder.encode(data32(4), UInt16(7)).blake2b256hash(),
        )

        let auditShard = RuntimeEvents.AuditShardRequestReceived(erasureRoot: data32(5), shardIndex: 8)
        #expect(
            try auditShard.generateRequestId() ==
                JamEncoder.encode(data32(5), UInt16(8)).blake2b256hash(),
        )

        let segmentShard = RuntimeEvents.SegmentShardRequestReceived(
            erasureRoot: data32(6),
            shardIndex: 9,
            segmentIndices: [10, 11],
        )
        #expect(
            try segmentShard.generateRequestId() ==
                JamEncoder.encode(data32(6), UInt16(9), [UInt16(10), UInt16(11)]).blake2b256hash(),
        )

        let bundle = RuntimeEvents.BundleRequestReceived(erasureRoot: data32(12))
        #expect(try bundle.generateRequestId() == JamEncoder.encode(data32(12)).blake2b256hash())

        let segment = RuntimeEvents.SegmentRequestReceived(segmentsRoot: data32(13), segmentIndices: [14, 15])
        #expect(
            try segment.generateRequestId() ==
                JamEncoder.encode(data32(13), [UInt16(14), UInt16(15)]).blake2b256hash(),
        )
    }

    @Test
    func requestIdsChangeWhenRequestPayloadChanges() throws {
        let first = RuntimeEvents.SegmentRequestReceived(segmentsRoot: data32(1), segmentIndices: [1, 2])
        let second = RuntimeEvents.SegmentRequestReceived(segmentsRoot: data32(1), segmentIndices: [1, 3])

        #expect(try first.generateRequestId() != second.generateRequestId())
    }

    @Test
    func responseConstructorsStoreSuccessValues() throws {
        let requestId = data32(1)

        let stateResponse = RuntimeEvents.StateRequestReceivedResponse(
            requestId: requestId,
            headerHash: data32(2),
            boundaryNodes: [],
            keyValuePairs: [(key: data31(3), value: Data([4, 5]))],
        )
        let stateValue = try stateResponse.result.get()
        #expect(stateResponse.requestId == requestId)
        #expect(stateValue.headerHash == data32(2))
        #expect(stateValue.keyValuePairs.first?.key == data31(3))
        #expect(stateValue.keyValuePairs.first?.value == Data([4, 5]))

        let workBundleResponse = RuntimeEvents.WorkPackageBundleReceivedResponse(
            workBundleHash: data32(6),
            workReportHash: data32(7),
            signature: data64(8),
        )
        let workBundleValue = try workBundleResponse.result.get()
        #expect(workBundleResponse.workBundleHash == data32(6))
        #expect(workBundleValue.workReportHash == data32(7))
        #expect(workBundleValue.signature == data64(8))

        let workReportResponse = RuntimeEvents.WorkReportReceivedResponse(workReportHash: data32(9))
        #expect(workReportResponse.workReportHash == data32(9))
        try workReportResponse.result.get()

        let preimageResponse = RuntimeEvents.PreimageRequestReceivedResponse(hash: data32(10), preimage: Data([11]))
        #expect(preimageResponse.hash == data32(10))
        #expect(try preimageResponse.result.get() == Data([11]))

        let bundleResponse = RuntimeEvents.BundleRequestReceivedResponse(
            requestId: data32(12),
            erasureRoot: data32(13),
            bundleData: Data([14]),
        )
        let bundleValue = try bundleResponse.result.get()
        #expect(bundleResponse.requestId == data32(12))
        #expect(bundleValue.erasureRoot == data32(13))
        #expect(bundleValue.bundleData == Data([14]))
    }

    @Test
    func availabilityResponseConstructorsStoreSuccessValues() throws {
        let shardDistribution = RuntimeEvents.ShardDistributionReceivedResponse(
            requestId: data32(1),
            bundleShard: Data([2]),
            segmentShards: [Data([3]), Data([4])],
            justification: .leaf,
        )
        let shardDistributionValue = try shardDistribution.result.get()
        #expect(shardDistribution.requestId == data32(1))
        #expect(shardDistributionValue.bundleShard == Data([2]))
        #expect(shardDistributionValue.segmentShards == [Data([3]), Data([4])])
        #expect(shardDistributionValue.justification == .leaf)

        let auditShard = RuntimeEvents.AuditShardRequestReceivedResponse(
            requestId: data32(5),
            erasureRoot: data32(6),
            shardIndex: 7,
            bundleShard: Data([8]),
            justification: .branch(left: data32(9), right: data32(10)),
        )
        let auditShardValue = try auditShard.result.get()
        #expect(auditShard.requestId == data32(5))
        #expect(auditShardValue.erasureRoot == data32(6))
        #expect(auditShardValue.shardIndex == 7)
        #expect(auditShardValue.bundleShard == Data([8]))
        #expect(auditShardValue.justification == .branch(left: data32(9), right: data32(10)))

        let segmentShard = RuntimeEvents.SegmentShardRequestReceivedResponse(
            requestId: data32(11),
            segments: [
                SegmentShard(shard: Data([12]), justification: .singleHash(data32(13))),
            ],
        )
        let segmentShardValue = try segmentShard.result.get()
        #expect(segmentShard.requestId == data32(11))
        #expect(segmentShardValue.first?.shard == Data([12]))
        #expect(segmentShardValue.first?.justification == .singleHash(data32(13)))

        let segment = RuntimeEvents.SegmentRequestReceivedResponse(
            requestId: data32(14),
            segmentsRoot: data32(15),
            segments: [Data([16]), Data([17])],
        )
        let segmentValue = try segment.result.get()
        #expect(segment.requestId == data32(14))
        #expect(segmentValue.segmentsRoot == data32(15))
        #expect(segmentValue.segments == [Data([16]), Data([17])])
    }

    @Test
    func responseConstructorsStoreFailures() {
        assertFailure(RuntimeEvents.StateRequestReceivedResponse(requestId: data32(1), error: RuntimeEventsTestError.sample).result)
        assertFailure(RuntimeEvents.WorkPackageBundleReceivedResponse(workBundleHash: data32(2), error: RuntimeEventsTestError.sample).result)
        assertFailure(RuntimeEvents.WorkReportReceivedResponse(workReportHash: data32(3), error: RuntimeEventsTestError.sample).result)
        assertFailure(RuntimeEvents.PreimageRequestReceivedResponse(hash: data32(4), error: RuntimeEventsTestError.sample).result)
        assertFailure(RuntimeEvents.BundleRequestReceivedResponse(requestId: data32(5), error: RuntimeEventsTestError.sample).result)
        assertFailure(RuntimeEvents.ShardDistributionReceivedResponse(requestId: data32(6), error: RuntimeEventsTestError.sample).result)
        assertFailure(RuntimeEvents.AuditShardRequestReceivedResponse(requestId: data32(7), error: RuntimeEventsTestError.sample).result)
        assertFailure(RuntimeEvents.SegmentShardRequestReceivedResponse(requestId: data32(8), error: RuntimeEventsTestError.sample).result)
        assertFailure(RuntimeEvents.SegmentRequestReceivedResponse(requestId: data32(9), error: RuntimeEventsTestError.sample).result)
    }

    @Test
    func networkEventInitializersStorePayloads() {
        let config = ProtocolConfigRef.tiny
        let workPackage = WorkPackage.dummy(config: config).asRef()
        let bundle = WorkPackageBundle.dummy(config: config)
        let mappings = [SegmentsRootMapping(workPackageHash: data32(1), segmentsRoot: data32(2))]

        let submitted = RuntimeEvents.WorkPackagesSubmitted(
            coreIndex: 1,
            workPackage: workPackage,
            extrinsics: [Data([3])],
        )
        #expect(submitted.coreIndex == 1)
        #expect(submitted.workPackage.hash == workPackage.hash)
        #expect(submitted.extrinsics == [Data([3])])

        let received = RuntimeEvents.WorkPackagesReceived(
            coreIndex: 2,
            workPackage: workPackage,
            extrinsics: [Data([4])],
        )
        #expect(received.coreIndex == 2)
        #expect(received.workPackage.hash == workPackage.hash)
        #expect(received.extrinsics == [Data([4])])

        let ready = RuntimeEvents.WorkPackageBundleReady(
            target: data32(5),
            coreIndex: 3,
            bundle: bundle,
            segmentsRootMappings: mappings,
        )
        #expect(ready.target == data32(5))
        #expect(ready.coreIndex == 3)
        #expect(ready.bundle == bundle)
        #expect(ready.segmentsRootMappings == mappings)

        let bundleReceived = RuntimeEvents.WorkPackageBundleReceived(
            coreIndex: 4,
            bundle: bundle,
            segmentsRootMappings: mappings,
        )
        #expect(bundleReceived.coreIndex == 4)
        #expect(bundleReceived.bundle == bundle)
        #expect(bundleReceived.segmentsRootMappings == mappings)

        let reply = RuntimeEvents.WorkPackageBundleReceivedReply(
            source: data32(6),
            workReportHash: data32(7),
            signature: data64(8),
        )
        #expect(reply.source == data32(6))
        #expect(reply.workReportHash == data32(7))
        #expect(reply.signature == data64(8))

        let report = WorkReport.dummy(config: config)
        let signatures = [ValidatorSignature(validatorIndex: 9, signature: data64(10))]
        let generated = RuntimeEvents.WorkReportGenerated(workReport: report, slot: 11, signatures: signatures)
        #expect(generated.workReport == report)
        #expect(generated.slot == 11)
        #expect(generated.signatures == signatures)

        let reportReceived = RuntimeEvents.WorkReportReceived(workReport: report, slot: 12, signatures: signatures)
        #expect(reportReceived.workReport == report)
        #expect(reportReceived.slot == 12)
        #expect(reportReceived.signatures == signatures)
    }

    @Test
    func announcementEventInitializersStorePayloads() throws {
        var bitfield = ConfigSizeBitString<ProtocolConfig.TotalNumberOfCores>(config: ProtocolConfigRef.tiny)
        try bitfield.set(1, to: true)

        let assurance = RuntimeEvents.AssuranceDistributionReceived(
            headerHash: data32(1),
            bitfield: bitfield,
            signature: data64(2),
        )
        #expect(assurance.headerHash == data32(1))
        #expect(assurance.bitfield == bitfield)
        #expect(assurance.signature == data64(2))

        let preimageAnnouncement = RuntimeEvents.PreimageAnnouncementReceived(
            serviceID: 3,
            hash: data32(4),
            preimageLength: 5,
        )
        #expect(preimageAnnouncement.serviceID == 3)
        #expect(preimageAnnouncement.hash == data32(4))
        #expect(preimageAnnouncement.preimageLength == 5)

        let preimageRequest = RuntimeEvents.PreimageRequestReceived(hash: data32(6))
        #expect(preimageRequest.hash == data32(6))

        let judgement = RuntimeEvents.JudgementPublicationReceived(
            epochIndex: 7,
            validatorIndex: 8,
            validity: 1,
            workReportHash: data32(9),
            signature: data64(10),
        )
        #expect(judgement.epochIndex == 7)
        #expect(judgement.validatorIndex == 8)
        #expect(judgement.validity == 1)
        #expect(judgement.workReportHash == data32(9))
        #expect(judgement.signature == data64(10))

        let announcement = Announcement(
            workReports: [.init(coreIndex: 11, workReportHash: data32(12))],
            signature: data64(13),
        )
        let audit = RuntimeEvents.AuditAnnouncementReceived(
            headerHash: data32(14),
            tranche: 15,
            announcement: announcement,
            evidence: .firstTranche(data96(16)),
        )
        #expect(audit.headerHash == data32(14))
        #expect(audit.tranche == 15)
        #expect(audit.announcement == announcement)
        #expect(audit.evidence == .firstTranche(data96(16)))
    }

    private func assertFailure(_ result: Result<some Any, Error>) {
        if case .success = result {
            Issue.record("Expected failure result")
        }
    }

    private func data96(_ byte: UInt8) -> Data96 {
        Data96(Data(repeating: byte, count: 96))!
    }
}
