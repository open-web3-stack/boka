import Codec
import Utils

public struct SegmentShard: Sendable, Codable {
    public let shard: Data
    public let justification: Justification?

    public init(shard: Data, justification: Justification? = nil) throws {
        guard shard.count == 12 else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Segment Shard must be exactly 12 bytes"
            ))
        }
        self.shard = shard
        self.justification = justification
    }
}
