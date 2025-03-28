import Blockchain
import Codec
import Foundation
import Utils

public struct StateRequest: Codable, Sendable, Equatable, Hashable {
    public enum StateRequestError: Error {
        case invalidKeyLength(actual: Int, expected: Int)
    }

    public var headerHash: Data32
    public var startKey: Data // [u8; 31]
    public var endKey: Data // [u8; 31]
    public var maxSize: UInt32

    public init(headerHash: Data32, startKey: Data, endKey: Data, maxSize: UInt32) throws {
        guard startKey.count == 31 else {
            throw StateRequestError.invalidKeyLength(actual: startKey.count, expected: 31)
        }
        guard endKey.count == 31 else {
            throw StateRequestError.invalidKeyLength(actual: endKey.count, expected: 31)
        }

        self.headerHash = headerHash
        self.startKey = startKey
        self.endKey = endKey
        self.maxSize = maxSize
    }
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
                debugDescription: "unexpected data \(data)"
            ))
        }

        let decoder = JamDecoder(data: data, config: config)
        let headerHash = try decoder.decode(Data32.self)
        let startKey = try decoder.decode(Data.self)
        let endKey = try decoder.decode(Data.self)
        let maxSize = try decoder.decode(UInt32.self)
        guard startKey.count == 31 || endKey.count == 31 else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "key length must be 31 bytes"
            ))
        }
        return try StateRequest(headerHash: headerHash, startKey: startKey, endKey: endKey, maxSize: maxSize)
    }
}
