import Codec
import Utils

public enum Justification: Codable, Sendable, Equatable {
    case singleHash(Data32) // 0 ++ Hash
    case doubleHash(Data32, Data32) // 1 ++ Hash ++ Hash
    case segmentShard(Data12) // 2 ++ Segment Shard (12 bytes)
}
