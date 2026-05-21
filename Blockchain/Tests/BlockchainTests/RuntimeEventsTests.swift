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
                JamEncoder.encode(data32(1), data31(2), data31(3), UInt32(128)).blake2b256hash()
        )

        let shardDistribution = RuntimeEvents.ShardDistributionReceived(erasureRoot: data32(4), shardIndex: 7)
        #expect(
            try shardDistribution.generateRequestId() ==
                JamEncoder.encode(data32(4), UInt16(7)).blake2b256hash()
        )

        let auditShard = RuntimeEvents.AuditShardRequestReceived(erasureRoot: data32(5), shardIndex: 8)
        #expect(
            try auditShard.generateRequestId() ==
                JamEncoder.encode(data32(5), UInt16(8)).blake2b256hash()
        )

        let segmentShard = RuntimeEvents.SegmentShardRequestReceived(
            erasureRoot: data32(6),
            shardIndex: 9,
            segmentIndices: [10, 11],
        )
        #expect(
            try segmentShard.generateRequestId() ==
                JamEncoder.encode(data32(6), UInt16(9), [UInt16(10), UInt16(11)]).blake2b256hash()
        )

        let bundle = RuntimeEvents.BundleRequestReceived(erasureRoot: data32(12))
        #expect(try bundle.generateRequestId() == JamEncoder.encode(data32(12)).blake2b256hash())

        let segment = RuntimeEvents.SegmentRequestReceived(segmentsRoot: data32(13), segmentIndices: [14, 15])
        #expect(
            try segment.generateRequestId() ==
                JamEncoder.encode(data32(13), [UInt16(14), UInt16(15)]).blake2b256hash()
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
    func responseConstructorsStoreFailures() {
        assertFailure(RuntimeEvents.StateRequestReceivedResponse(requestId: data32(1), error: RuntimeEventsTestError.sample).result)
        assertFailure(RuntimeEvents.WorkPackageBundleReceivedResponse(workBundleHash: data32(2), error: RuntimeEventsTestError.sample).result)
        assertFailure(RuntimeEvents.WorkReportReceivedResponse(workReportHash: data32(3), error: RuntimeEventsTestError.sample).result)
        assertFailure(RuntimeEvents.PreimageRequestReceivedResponse(hash: data32(4), error: RuntimeEventsTestError.sample).result)
        assertFailure(RuntimeEvents.BundleRequestReceivedResponse(requestId: data32(5), error: RuntimeEventsTestError.sample).result)
    }

    private func assertFailure<Success>(_ result: Result<Success, Error>) {
        if case .success = result {
            Issue.record("Expected failure result")
        }
    }
}

