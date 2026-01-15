import Codec
import Utils

public enum Justification: Sendable, Equatable {
    case singleHash(Data32) // 0 ++ Hash
    case doubleHash(Data32, Data32) // 1 ++ Hash ++ Hash
    case segmentShard(Data) // 2 ++ Segment Shard (variable)
    case copath([JustificationStep]) // 3 ++ Copath
}

public enum JustificationStep: Sendable, Equatable, Codable {
    case left(Data32)
    case right(Data32)
}

extension Justification: Codable {
    enum CodingKeys: String, CodingKey {
        case singleHash
        case doubleHash
        case segmentShard
        case copath
    }

    public init(from decoder: Decoder) throws {
        if decoder.isJamCodec {
            var container = try decoder.unkeyedContainer()
            let variant = try container.decode(UInt8.self)

            switch variant {
            case 0:
                let hash = try container.decode(Data32.self)
                self = .singleHash(hash)
            case 1:
                let hash1 = try container.decode(Data32.self)
                let hash2 = try container.decode(Data32.self)
                self = .doubleHash(hash1, hash2)
            case 2:
                let shard = try container.decode(Data.self)
                self = .segmentShard(shard)
            case 3:
                let steps = try container.decode([JustificationStep].self)
                self = .copath(steps)
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid Justification variant: \(variant)"
                    )
                )
            }
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let hash = try container.decodeIfPresent(Data32.self, forKey: .singleHash) {
                self = .singleHash(hash)
            } else if let hashes = try container.decodeIfPresent([Data32].self, forKey: .doubleHash), hashes.count == 2 {
                self = .doubleHash(hashes[0], hashes[1])
            } else if let shard = try container.decodeIfPresent(Data.self, forKey: .segmentShard) {
                self = .segmentShard(shard)
            } else if let steps = try container.decodeIfPresent([JustificationStep].self, forKey: .copath) {
                self = .copath(steps)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Could not decode Justification"
                    )
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        if encoder.isJamCodec {
            var container = encoder.unkeyedContainer()

            switch self {
            case let .singleHash(hash):
                try container.encode(UInt8(0))
                try container.encode(hash)
            case let .doubleHash(hash1, hash2):
                try container.encode(UInt8(1))
                try container.encode(hash1)
                try container.encode(hash2)
            case let .segmentShard(shard):
                try container.encode(UInt8(2))
                try container.encode(shard)
            case let .copath(steps):
                try container.encode(UInt8(3))
                try container.encode(steps)
            }
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case let .singleHash(hash):
                try container.encode(hash, forKey: .singleHash)
            case let .doubleHash(hash1, hash2):
                try container.encode([hash1, hash2], forKey: .doubleHash)
            case let .segmentShard(shard):
                try container.encode(shard, forKey: .segmentShard)
            case let .copath(steps):
                try container.encode(steps, forKey: .copath)
            }
        }
    }
}
