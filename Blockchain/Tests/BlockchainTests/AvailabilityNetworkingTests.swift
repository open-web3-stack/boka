import Foundation
#if DISABLED
    // Disabled: Needs refactoring for API changes
    import Testing
    import TracingUtils
    import Utils

    @testable import Blockchain

    /// Unit tests for JAMNP-S networking protocol messages
    struct AvailabilityNetworkingTests {
        // MARK: - ShardRequest Tests

        @Test
        func shardRequestEncodeDecode() throws {
            let request = ShardRequest(
                erasureRoot: Data32([
                    1,
                    2,
                    3,
                    4,
                    5,
                    6,
                    7,
                    8,
                    9,
                    10,
                    11,
                    12,
                    13,
                    14,
                    15,
                    16,
                    17,
                    18,
                    19,
                    20,
                    21,
                    22,
                    23,
                    24,
                    25,
                    26,
                    27,
                    28,
                    29,
                    30,
                    31,
                    32,
                ]),
                shardIndex: 123,
                segmentIndices: nil
            )

            let encoded = try request.encode()
            let decoded = try ShardRequest.decode(encoded)

            #expect(decoded.erasureRoot == request.erasureRoot)
            #expect(decoded.shardIndex == request.shardIndex)
            #expect(decoded.segmentIndices == nil)
        }

        @Test
        func shardRequestWithSegmentsEncodeDecode() throws {
            let segmentIndices: [UInt16] = [0, 100, 500, 1022]
            let request = ShardRequest(
                erasureRoot: Data32.random(),
                shardIndex: 456,
                segmentIndices: segmentIndices
            )

            let encoded = try request.encode()
            let decoded = try ShardRequest.decode(encoded)

            #expect(decoded.erasureRoot == request.erasureRoot)
            #expect(decoded.shardIndex == request.shardIndex)
            #expect(decoded.segmentIndices == segmentIndices)
        }

        @Test
        func shardRequestInvalidLength() {
            let invalidData = Data([1, 2, 3])

            #expect(throws: AvailabilityNetworkingError.self) {
                try ShardRequest.decode(invalidData)
            }
        }

        // MARK: - ShardResponse Tests

        @Test
        func shardResponseEncodeDecode() throws {
            let bundleShard = Data([1, 2, 3, 4, 5])
            let segmentShards = [Data([6, 7]), Data([8, 9])]
            let justification = Justification.leaf

            let response = ShardResponse(
                bundleShard: bundleShard,
                segmentShards: segmentShards,
                justification: justification
            )

            let encoded = try response.encode()
            let decoded = try ShardResponse.decode(encoded)

            #expect(decoded.bundleShard == bundleShard)
            #expect(decoded.segmentShards == segmentShards)

            switch decoded.justification {
            case .leaf:
                break // Expected
            default:
                Issue.record("Expected leaf justification")
            }
        }

        @Test
        func shardResponseWithJustificationEncodeDecode() throws {
            let bundleShard = Data([1, 2, 3, 4, 5])
            let segmentShards = [Data([6, 7]), Data([8, 9])]
            let leftHash = Data32([UInt8](repeating: 1, count: 32))
            let rightHash = Data32([UInt8](repeating: 2, count: 32))
            let justification = Justification.branch(left: leftHash, right: rightHash)

            let response = ShardResponse(
                bundleShard: bundleShard,
                segmentShards: segmentShards,
                justification: justification
            )

            let encoded = try response.encode()
            let decoded = try ShardResponse.decode(encoded)

            #expect(decoded.bundleShard == bundleShard)
            #expect(decoded.segmentShards.count == 2)

            switch decoded.justification {
            case let .branch(l, r):
                #expect(l == leftHash)
                #expect(r == rightHash)
            default:
                Issue.record("Expected branch justification")
            }
        }

        @Test
        func shardResponseInvalidLength() {
            let invalidData = Data([1, 2, 3])

            #expect(throws: AvailabilityNetworkingError.self) {
                try ShardResponse.decode(invalidData)
            }
        }

        // MARK: - Justification Tests

        @Test
        func justificationLeafEncodeDecode() throws {
            let justification = Justification.leaf
            let encoded = try justification.encode()
            let decoded = try Justification.decode(encoded)

            switch decoded {
            case .leaf:
                break // Expected
            default:
                Issue.record("Expected leaf justification")
            }
        }

        @Test
        func justificationBranchEncodeDecode() throws {
            let leftHash = Data32([UInt8](repeating: 1, count: 32))
            let rightHash = Data32([UInt8](repeating: 2, count: 32))
            let justification = Justification.branch(left: leftHash, right: rightHash)

            let encoded = try justification.encode()
            let decoded = try Justification.decode(encoded)

            switch decoded {
            case let .branch(l, r):
                #expect(l == leftHash)
                #expect(r == rightHash)
            default:
                Issue.record("Expected branch justification")
            }
        }

        @Test
        func justificationSegmentShardEncodeDecode() throws {
            let shardData = Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
            let justification = Justification.segmentShard(shardData)

            let encoded = try justification.encode()
            let decoded = try Justification.decode(encoded)

            switch decoded {
            case let .segmentShard(data):
                #expect(data == shardData)
            default:
                Issue.record("Expected segment shard justification")
            }
        }

        @Test
        func justificationCopathEncodeDecode() throws {
            let steps: [Justification.JustificationStep] = [
                .left(Data32([UInt8](repeating: 1, count: 32))),
                .right(Data32([UInt8](repeating: 2, count: 32))),
                .left(Data32([UInt8](repeating: 3, count: 32))),
            ]
            let justification = Justification.copath(steps)

            let encoded = try justification.encode()
            let decoded = try Justification.decode(encoded)

            switch decoded {
            case let .copath(decodedSteps):
                #expect(decodedSteps.count == 3)
                switch decodedSteps[0] {
                case let .left(hash):
                    #expect(hash == Data32([UInt8](repeating: 1, count: 32)))
                default:
                    Issue.record("Expected left step")
                }
            default:
                Issue.record("Expected copath justification")
            }
        }

        @Test
        func justificationInvalidDiscriminator() {
            // Invalid discriminator (3) followed by some data
            let invalidData = Data([3, 1, 2, 3, 4])

            #expect(throws: AvailabilityNetworkingError.self) {
                try Justification.decode(invalidData)
            }
        }

        @Test
        func justificationIncompleteBranch() {
            // Discriminator 1 (branch) but not enough data
            let invalidData = Data([1, 1, 2, 3])

            #expect(throws: AvailabilityNetworkingError.self) {
                try Justification.decode(invalidData)
            }
        }

        // MARK: - BundleRequest Tests

        @Test
        func bundleRequestEncodeDecode() throws {
            let erasureRoot = Data32([UInt8](repeating: 5, count: 32))
            let request = BundleRequest(erasureRoot: erasureRoot)

            let encoded = request.encode()
            let decoded = try BundleRequest.decode(encoded)

            #expect(decoded.erasureRoot == erasureRoot)
        }

        @Test
        func bundleRequestInvalidLength() {
            let invalidData = Data([1, 2, 3])

            #expect(throws: AvailabilityNetworkingError.self) {
                try BundleRequest.decode(invalidData)
            }
        }

        // MARK: - BundleResponse Tests

        @Test
        func bundleResponseEncodeDecode() throws {
            let bundleData = Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
            let response = BundleResponse(bundle: bundleData)

            let encoded = try response.encode()
            let decoded = try BundleResponse.decode(encoded)

            #expect(decoded.bundle == bundleData)
        }

        @Test
        func bundleResponseLargeDataEncodeDecode() throws {
            // Test with larger data (simulating actual bundle)
            let bundleData = Data((0 ..< 10000).map { _ in UInt8.random(in: 0 ... 255) })
            let response = BundleResponse(bundle: bundleData)

            let encoded = try response.encode()
            let decoded = try BundleResponse.decode(encoded)

            #expect(decoded.bundle == bundleData)
        }

        @Test
        func bundleResponseInvalidLength() {
            let invalidData = Data([1, 2, 3])

            #expect(throws: AvailabilityNetworkingError.self) {
                try BundleResponse.decode(invalidData)
            }
        }

        @Test
        func bundleResponseIncompleteData() {
            // Length prefix says 100 bytes but only 3 bytes provided
            var data = Data()
            let length = UInt32(100).littleEndian
            withUnsafeBytes(of: length) { data.append(Data($0)) }
            data.append(Data([1, 2, 3]))

            #expect(throws: AvailabilityNetworkingError.self) {
                try BundleResponse.decode(data)
            }
        }

        // MARK: - SegmentRequest Tests

        @Test
        func segmentRequestEncodeDecode() throws {
            let segmentsRoot = Data32([UInt8](repeating: 6, count: 32))
            let segmentIndices: [UInt16] = [0, 100, 500, 1000]
            let request = SegmentRequest(segmentsRoot: segmentsRoot, segmentIndices: segmentIndices)

            let encoded = try request.encode()
            let decoded = try SegmentRequest.decode(encoded)

            #expect(decoded.segmentsRoot == segmentsRoot)
            #expect(decoded.segmentIndices == segmentIndices)
        }

        @Test
        func segmentRequestEmptyIndices() throws {
            let segmentsRoot = Data32([UInt8](repeating: 7, count: 32))
            let segmentIndices: [UInt16] = []
            let request = SegmentRequest(segmentsRoot: segmentsRoot, segmentIndices: segmentIndices)

            let encoded = try request.encode()
            let decoded = try SegmentRequest.decode(encoded)

            #expect(decoded.segmentsRoot == segmentsRoot)
            #expect(decoded.segmentIndices.isEmpty)
        }

        @Test
        func segmentRequestInvalidLength() {
            let invalidData = Data([1, 2, 3])

            #expect(throws: AvailabilityNetworkingError.self) {
                try SegmentRequest.decode(invalidData)
            }
        }

        @Test
        func segmentRequestIncompleteIndices() {
            // Has count but not enough indices
            var data = Data()
            let root = Data32([UInt8](repeating: 8, count: 32))
            data.append(root.data)

            let count = UInt32(10).littleEndian
            withUnsafeBytes(of: count) { data.append(Data($0)) }

            // Only add 2 indices instead of 10
            data.append(withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) })
            data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })

            #expect(throws: AvailabilityNetworkingError.self) {
                try SegmentRequest.decode(data)
            }
        }

        // MARK: - SegmentResponse Tests

        @Test
        func segmentResponseEncodeDecode() throws {
            var segments: [Data4104] = []
            for i in 0 ..< 5 {
                var data = Data(count: 4104)
                data[0] = UInt8(i)
                segments.append(Data4104(data)!)
            }

            let importProofs: [[Data32]] = [
                [Data32(Data([UInt8](repeating: 1, count: 32))!)!, Data32(Data([UInt8](repeating: 2, count: 32))!)!],
                [Data32(Data([UInt8](repeating: 3, count: 32))!)!],
                [],
                [
                    Data32(Data([UInt8](repeating: 4, count: 32))!)!,
                    Data32(Data([UInt8](repeating: 5, count: 32))!)!,
                    Data32(Data([UInt8](repeating: 6, count: 32))!)!,
                ],
                [Data32(Data([UInt8](repeating: 7, count: 32))!)],
            ]

            let response = SegmentResponse(segments: segments, importProofs: importProofs)

            let encoded = try response.encode()
            let decoded = try SegmentResponse.decode(encoded)

            #expect(decoded.segments.count == 5)
            #expect(decoded.segments[0].data[0] == 0)
            #expect(decoded.segments[4].data[0] == 4)

            #expect(decoded.importProofs.count == 5)
            #expect(decoded.importProofs[0].count == 2)
            #expect(decoded.importProofs[2].isEmpty)
        }

        @Test
        func segmentResponseEmptySegmentsEncodeDecode() throws {
            let segments: [Data4104] = []
            let importProofs: [[Data32]] = []

            let response = SegmentResponse(segments: segments, importProofs: importProofs)

            let encoded = try response.encode()
            let decoded = try SegmentResponse.decode(encoded)

            #expect(decoded.segments.isEmpty)
            #expect(decoded.importProofs.isEmpty)
        }

        @Test
        func segmentResponseInvalidLength() {
            let invalidData = Data([1, 2, 3])

            #expect(throws: AvailabilityNetworkingError.self) {
                try SegmentResponse.decode(invalidData)
            }
        }

        @Test
        func segmentResponseIncompleteSegment() {
            // Segment count says 1 but no segment data
            var data = Data()
            let count = UInt32(1).littleEndian
            withUnsafeBytes(of: count) { data.append(Data($0)) }

            #expect(throws: AvailabilityNetworkingError.self) {
                try SegmentResponse.decode(data)
            }
        }

        // MARK: - Message Size Limits Tests

        @Test
        func messageSizeLimitsConstants() {
            #expect(MessageSizeLimits.maxShardResponseSize == 1024 * 1024)
            #expect(MessageSizeLimits.maxSegmentShardsPerStream == 2 * 3072)
            #expect(MessageSizeLimits.maxSegmentsPerStream == 3072)
        }

        // MARK: - Request Type Tests

        @Test
        func requestTypeRawValues() {
            #expect(ShardRequestType.auditShard.rawValue == 138)
            #expect(ShardRequestType.segmentShardsFast.rawValue == 139)
            #expect(ShardRequestType.segmentShardsVerified.rawValue == 140)
            #expect(ShardRequestType.fullBundle.rawValue == 147)
            #expect(ShardRequestType.reconstructedSegments.rawValue == 148)
        }

        // MARK: - Node Role Tests

        @Test
        func nodeRoleRawValues() {
            #expect(NodeRole.auditor.rawValue == 0)
            #expect(NodeRole.guarantor.rawValue == 1)
            #expect(NodeRole.assurer.rawValue == 2)
            #expect(NodeRole.builder.rawValue == 3)
        }

        // MARK: - Edge Cases

        @Test
        func shardRequestMaxIndices() throws {
            // Test with maximum number of segment indices
            let segmentIndices = [UInt16](0 ..< UInt16(MessageSizeLimits.maxSegmentShardsPerStream))
            let request = ShardRequest(
                erasureRoot: Data32.random(),
                shardIndex: 0,
                segmentIndices: segmentIndices
            )

            let encoded = try request.encode()
            let decoded = try ShardRequest.decode(encoded)

            #expect(decoded.segmentIndices?.count == MessageSizeLimits.maxSegmentShardsPerStream)
        }

        @Test
        func shardRequestZeroShardIndex() throws {
            let request = ShardRequest(
                erasureRoot: Data32.random(),
                shardIndex: 0,
                segmentIndices: nil
            )

            let encoded = try request.encode()
            let decoded = try ShardRequest.decode(encoded)

            #expect(decoded.shardIndex == 0)
        }

        @Test
        func shardRequestMaxShardIndex() throws {
            let request = ShardRequest(
                erasureRoot: Data32.random(),
                shardIndex: 1022,
                segmentIndices: nil
            )

            let encoded = try request.encode()
            let decoded = try ShardRequest.decode(encoded)

            #expect(decoded.shardIndex == 1022)
        }
    }
#endif
