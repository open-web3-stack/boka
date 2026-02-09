import Blockchain
import Codec
import Foundation
import Utils

public struct ShardDistributionMessage: Codable, Sendable, Equatable, Hashable {
    public var erasureRoot: Data32
    public var shardIndex: UInt16

    public init(erasureRoot: Data32, shardIndex: UInt16) {
        self.erasureRoot = erasureRoot
        self.shardIndex = shardIndex
    }
}

extension ShardDistributionMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> ShardDistributionMessage {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data \(data)",
            ))
        }
        return try JamDecoder.decode(ShardDistributionMessage.self, from: data, withConfig: config)
    }
}
