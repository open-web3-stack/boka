import Blockchain
import Codec
import Foundation
import Utils

public struct AuditShardRequestMessage: Codable, Sendable, Equatable, Hashable {
    public var erasureRoot: Data32
    public var shardIndex: UInt32

    public init(erasureRoot: Data32, shardIndex: UInt32) {
        self.erasureRoot = erasureRoot
        self.shardIndex = shardIndex
    }
}

extension AuditShardRequestMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> AuditShardRequestMessage {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data"
            ))
        }
        return try JamDecoder.decode(AuditShardRequestMessage.self, from: data, withConfig: config)
    }
}
