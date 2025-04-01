import Blockchain
import Codec
import Foundation
import Utils

public struct StateRequest: Codable, Sendable, Equatable, Hashable {
    public var headerHash: Data32
    public var startKey: Data31 // [u8; 31]
    public var endKey: Data31 // [u8; 31]
    public var maxSize: UInt32

    public init(headerHash: Data32, startKey: Data31, endKey: Data31, maxSize: UInt32) {
        self.headerHash = headerHash
        self.startKey = startKey
        self.endKey = endKey
        self.maxSize = maxSize
    }
}

extension StateRequest: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> StateRequest {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data \(data)"
            ))
        }
        return try JamDecoder.decode(StateRequest.self, from: data, withConfig: config)
    }
}
