import Blockchain
import Codec
import Foundation
import Utils

public struct AssuranceDistributionMessage: Sendable, Equatable, Codable, Hashable {
    public let headerHash: Data32
    public let bitfield: Data // [u8; 43] (One bit per core)
    public let signature: Ed25519Signature

    public init(headerHash: Data32, bitfield: Data, signature: Ed25519Signature) throws {
        guard bitfield.count == 43 else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Bitfield must be exactly 43 bytes, but received \(bitfield.count) bytes"
            ))
        }
        self.headerHash = headerHash
        self.bitfield = bitfield
        self.signature = signature
    }
}

extension AssuranceDistributionMessage {
    public func encode() throws -> Data {
        try JamEncoder.encode(self)
    }

    public static func decode(data: Data, config: ProtocolConfigRef) throws -> AssuranceDistributionMessage {
        let message = try JamDecoder.decode(AssuranceDistributionMessage.self, from: data, withConfig: config)
        guard message.bitfield.count == 43 else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Decoded bitfield must be exactly 43 bytes, but received \(message.bitfield.count) bytes"
            ))
        }
        return message
    }
}
