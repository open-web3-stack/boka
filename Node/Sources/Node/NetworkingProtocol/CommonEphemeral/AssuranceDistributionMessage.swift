import Blockchain
import Codec
import Foundation
import Utils

public struct AssuranceDistributionMessage: Sendable, Equatable, Codable, Hashable {
    public let headerHash: Data32
    public let bitfield: ConfigSizeBitString<ProtocolConfig.TotalNumberOfCores>
    public let signature: Ed25519Signature

    public init(headerHash: Data32, bitfield: ConfigSizeBitString<ProtocolConfig.TotalNumberOfCores>, signature: Ed25519Signature) {
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
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data",
            ))
        }

        return try JamDecoder.decode(Self.self, from: data, withConfig: config)
    }
}
