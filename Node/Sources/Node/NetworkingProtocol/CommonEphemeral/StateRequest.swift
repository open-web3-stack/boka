import Blockchain
import Codec
import Foundation
import Utils

public struct StateRequest: Codable, Sendable, Equatable, Hashable {
    public var headerHash: Data32
    public var startKey: Data31
    public var endKey: Data31
    public var maxSize: UInt32
}

extension StateRequest: CEMessage {
    public func encode() throws -> [Data] {
        let encoder = JamEncoder()
        try encoder.encode(headerHash)
        try encoder.encode(startKey)
        try encoder.encode(endKey)
        try encoder.encode(maxSize)
        return [encoder.data]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> StateRequest {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "missing data"
            ))
        }

        let decoder = JamDecoder(data: data, config: config)
        let headerHash = try decoder.decode(Data32.self)
        let startKey = try decoder.decode(Data31.self)
        let endKey = try decoder.decode(Data31.self)
        let maxSize = try decoder.decode(UInt32.self)

        return StateRequest(headerHash: headerHash, startKey: startKey, endKey: endKey, maxSize: maxSize)
    }
}
