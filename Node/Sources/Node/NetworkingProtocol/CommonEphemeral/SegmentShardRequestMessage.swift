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
        let encoder = JamEncoder()
        try encoder.encode(erasureRoot)
        try encoder.encode(shardIndex)
        try encoder.encode(UInt32(segmentIndices.count))
        try encoder.encode(segmentIndices)
        return [encoder.data]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> SegmentShardRequestMessage {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data \(data)"
            ))
        }

        let decoder = JamDecoder(data: data, config: config)
        let erasureRoot = try decoder.decode(Data32.self)
        let shardIndex = try decoder.decode(UInt32.self)
        let count = try decoder.decode(UInt32.self)
        let segmentIndices = try decoder.decode([UInt16].self)

        guard segmentIndices.count == count else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Segment index count mismatch"
            ))
        }

        return try SegmentShardRequestMessage(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            segmentIndices: segmentIndices
        )
    }
}
