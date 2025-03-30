import Codec
import Utils

public struct SegmentShard: Sendable, Codable {
    public let shard: Data12
    public let justification: Justification?

    public init(shard: Data12, justification: Justification? = nil) {
        self.shard = shard
        self.justification = justification
    }
}
