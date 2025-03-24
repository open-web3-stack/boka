import Codec
import Utils

public enum Justification: Codable, Sendable {
    case singleHash(Data32) // 0 ++ Hash
    case doubleHash(Data32, Data32) // 1 ++ Hash ++ Hash
    case segmentShard(Data) // 2 ++ Segment Shard (12 bytes)
}

extension Justification {
    public func encode() throws -> [Data] {
        let encoder = JamEncoder()
        switch self {
        case let .singleHash(hash):
            try encoder.encode(0)
            try encoder.encode(hash)
        case let .doubleHash(hash1, hash2):
            try encoder.encode(1)
            try encoder.encode(hash1)
            try encoder.encode(hash2)
        case let .segmentShard(segmentShard):
            try encoder.encode(2)
            try encoder.encode(segmentShard)
        }
        return [encoder.data]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> Justification {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "missing data"
            ))
        }

        let decoder = JamDecoder(data: data, config: config)
        let type = try decoder.decode(UInt8.self)

        switch type {
        case 0:
            let hash = try decoder.decode(Data32.self)
            return .singleHash(hash)
        case 1:
            let hash1 = try decoder.decode(Data32.self)
            let hash2 = try decoder.decode(Data32.self)
            return .doubleHash(hash1, hash2)
        case 2:
            let segmentShard = try decoder.decode(Data.self)
            guard segmentShard.count == 12 else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Segment Shard must be 12 bytes"
                ))
            }
            return .segmentShard(segmentShard)
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Invalid type value: \(type)"
            ))
        }
    }
}
