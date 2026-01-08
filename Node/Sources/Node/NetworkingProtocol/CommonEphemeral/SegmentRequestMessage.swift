import Blockchain
import Codec
import Foundation
import Networking

/// CE 148: Segment request
///
/// Request for one or more segments.
///
/// This protocol should be used by guarantors or builders to request import segments
/// from other guarantors in order to complete work-package bundles.
///
/// The number of segments requested in a single stream should not exceed W_M (W_M = 3072).
///
/// Protocol:
/// ```
/// Guarantor -> Guarantor
/// --> [Segments-Root ++ len++[Segment Index]]
/// --> FIN
/// <-- [Segment]
/// <-- [Import-Proof]
/// <-- FIN
/// ```
public struct SegmentRequestMessage: Codable, Sendable {
    public enum SegmentRequestError: Error {
        case segmentIndicesExceedLimit(maxAllowed: Int, actual: Int)
    }

    public struct SegmentRequest: Codable, Sendable {
        /// Segments root identifying the import data
        public let segmentsRoot: Data32

        /// Segment indices to request
        public let segmentIndices: [UInt16]

        public init(segmentsRoot: Data32, segmentIndices: [UInt16]) {
            self.segmentsRoot = segmentsRoot
            self.segmentIndices = segmentIndices
        }
    }

    /// Multiple segment requests (for different segments roots)
    public let requests: [SegmentRequest]

    /// Maximum number of segments that can be requested in a single stream (W_M)
    public static let maxSegmentsPerRequest = 3072

    public init(requests: [SegmentRequest]) throws {
        // Validate total segment count across all requests doesn't exceed W_M
        let totalSegments = requests.reduce(0) { $0 + $1.segmentIndices.count }
        guard totalSegments <= Self.maxSegmentsPerRequest else {
            throw SegmentRequestError.segmentIndicesExceedLimit(
                maxAllowed: Self.maxSegmentsPerRequest,
                actual: totalSegments
            )
        }
        self.requests = requests
    }

    public init(segmentsRoot: Data32, segmentIndices: [UInt16]) throws {
        let request = SegmentRequest(
            segmentsRoot: segmentsRoot,
            segmentIndices: segmentIndices
        )
        try self.init(requests: [request])
    }
}

// MARK: - CE Message Protocol

extension SegmentRequestMessage: CEMessage {
    public func encode() throws -> [Data] {
        // Message: [Segments-Root ++ len++[Segment Index]]
        var encoder = JamEncoder()
        try encoder.encode(UInt32(requests.count))

        for request in requests {
            try encoder.encode(request.segmentsRoot)
            try encoder.encode(UInt32(request.segmentIndices.count))
            for index in request.segmentIndices {
                try encoder.encode(index)
            }
        }

        return [encoder.data]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> SegmentRequestMessage {
        guard data.count == 1 else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Expected 1 message, got \(data.count)"
            ))
        }

        let decoder = JamDecoder(data: data[0], config: config)
        let requestsCount = try decoder.decode(UInt32.self)
        var requests: [SegmentRequest] = []

        for _ in 0 ..< requestsCount {
            let segmentsRoot = try decoder.decode(Data32.self)
            let indicesCount = try decoder.decode(UInt32.self)
            var segmentIndices: [UInt16] = []

            for _ in 0 ..< indicesCount {
                let index = try decoder.decode(UInt16.self)
                segmentIndices.append(index)
            }

            requests.append(SegmentRequest(
                segmentsRoot: segmentsRoot,
                segmentIndices: segmentIndices
            ))
        }

        // Validate total segment count doesn't exceed W_M
        return try SegmentRequestMessage(requests: requests)
    }
}
