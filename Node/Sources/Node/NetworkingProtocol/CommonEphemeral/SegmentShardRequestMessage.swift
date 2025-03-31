import Blockchain
import Codec
import Foundation
import Utils

public struct SegmentShardRequestMessage: Codable, Sendable, Equatable, Hashable {
    public enum SegmentShardError: Error {
        case segmentIndicesExceedLimit(maxAllowed: Int, actual: Int)
    }

    public let erasureRoot: Data32
    public let shardIndex: UInt32
    public let segmentIndices: [UInt16]

    public init(
        erasureRoot: Data32,
        shardIndex: UInt32,
        segmentIndices: [UInt16]
    ) throws {
        guard segmentIndices.count <= 2048 else {
            throw SegmentShardError.segmentIndicesExceedLimit(maxAllowed: 2048, actual: segmentIndices.count)
        }
        self.erasureRoot = erasureRoot
        self.shardIndex = shardIndex
        self.segmentIndices = segmentIndices
    }
}

extension SegmentShardRequestMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> SegmentShardRequestMessage {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data \(data)"
            ))
        }
        return try JamDecoder.decode(SegmentShardRequestMessage.self, from: data, withConfig: config)
    }
}
