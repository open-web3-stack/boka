import Blockchain
import Codec
import Foundation
import Utils

public struct ShardDistributionMessage: Codable, Sendable, Equatable, Hashable {
    public var erasureRoot: Data32
    public var shardIndex: UInt32

    public init(erasureRoot: Data32, shardIndex: UInt32) {
        self.erasureRoot = erasureRoot
        self.shardIndex = shardIndex
    }
}

extension ShardDistributionMessage: CEMessage {
    public func encode() throws -> [Data] {
        let encoder = JamEncoder()
        try encoder.encode(erasureRoot)
        try encoder.encode(shardIndex)
        return [encoder.data]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> ShardDistributionMessage {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "missing data"
            ))
        }

        let decoder = JamDecoder(data: data, config: config)
        let erasureRoot = try decoder.decode(Data32.self)
        let shardIndex = try decoder.decode(UInt32.self)

        return ShardDistributionMessage(erasureRoot: erasureRoot, shardIndex: shardIndex)
    }
}
