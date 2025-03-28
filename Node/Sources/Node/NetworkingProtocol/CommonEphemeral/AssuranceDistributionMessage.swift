import Blockchain
import Codec
import Foundation
import Utils

public struct AssuranceDistributionMessage: Sendable, Equatable, Codable, Hashable {
    public enum AssuranceDistributionError: Error {
        case invalidBitfieldLength(actual: Int, expected: Int)
        case unexpectedData
    }

    public let headerHash: Data32
    public let bitfield: Data // [u8; 43] (One bit per core)
    public let signature: Ed25519Signature

    public init(headerHash: Data32, bitfield: Data, signature: Ed25519Signature) throws {
        guard bitfield.count == 43 else {
            throw AssuranceDistributionError.invalidBitfieldLength(
                actual: bitfield.count,
                expected: 43
            )
        }
        self.headerHash = headerHash
        self.bitfield = bitfield
        self.signature = signature
    }
}

extension AssuranceDistributionMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> Self {
        guard let data = data.first else {
            throw AssuranceDistributionError.unexpectedData
        }

        let message = try JamDecoder.decode(Self.self, from: data, withConfig: config)
        guard message.bitfield.count == 43 else {
            throw AssuranceDistributionError.invalidBitfieldLength(
                actual: message.bitfield.count,
                expected: 43
            )
        }
        return message
    }
}
