import Codec
import Utils

public struct SegmentShard: Sendable, Codable {
    public let shard: Data
    public let justification: Justification?

    public init(shard: Data, justification: Justification? = nil) {
        self.shard = shard
        self.justification = justification
    }
}
