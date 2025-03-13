import Blockchain
import Codec
import Foundation
import Utils

public struct BlockRequest: Codable, Sendable, Equatable, Hashable {
    public enum Direction: UInt8, Codable, Sendable, Equatable, Hashable {
        case ascendingExcludsive = 0
        case descendingInclusive = 1
    }

    public var hash: Data32
    public var direction: Direction
    public var maxBlocks: UInt32
}

extension BlockRequest: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> BlockRequest {
        guard data.count == 1, let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data \(data)"
            ))
        }
        return try JamDecoder.decode(BlockRequest.self, from: data, withConfig: config)
    }
}
