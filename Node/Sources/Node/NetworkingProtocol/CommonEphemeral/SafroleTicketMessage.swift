import Blockchain
import Codec
import Foundation

public struct SafroleTicketMessage: Codable, Sendable, Equatable, Hashable {
    public var epochIndex: EpochIndex
    public var attempt: TicketIndex
    public var proof: BandersnatchRingVRFProof
}

extension SafroleTicketMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], withConfig: ProtocolConfigRef) throws -> SafroleTicketMessage {
        guard data.count == 1, let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data"
            ))
        }
        return try JamDecoder.decode(SafroleTicketMessage.self, from: data, withConfig: withConfig)
    }
}
