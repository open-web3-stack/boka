import Foundation
import ScaleCodec
import Utils

public struct ExtrinsicTickets: Sendable, Equatable {
    public struct TicketItem: Sendable, Equatable {
        public var attempt: TicketIndex
        public var signature: BandersnatchRingVRFProof

        public init(
            attempt: TicketIndex,
            signature: BandersnatchRingVRFProof
        ) {
            self.attempt = attempt
            self.signature = signature
        }
    }

    public var tickets: ConfigLimitedSizeArray<
        TicketItem,
        ProtocolConfig.Int0,
        ProtocolConfig.MaxTicketsPerExtrinsic
    >

    public init(
        tickets: ConfigLimitedSizeArray<
            TicketItem,
            ProtocolConfig.Int0,
            ProtocolConfig.MaxTicketsPerExtrinsic
        >
    ) {
        self.tickets = tickets
    }
}

extension ExtrinsicTickets: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> ExtrinsicTickets {
        ExtrinsicTickets(tickets: ConfigLimitedSizeArray(config: config))
    }
}

extension ExtrinsicTickets.TicketItem: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            attempt: decoder.decode(),
            signature: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(attempt)
        try encoder.encode(signature)
    }
}

extension ExtrinsicTickets: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            tickets: ConfigLimitedSizeArray(config: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(tickets)
    }
}

extension ExtrinsicTickets {
    public func getTickets(_ verifier: Verifier, _ entropy: Data32) throws -> [Ticket] {
        try tickets.array.map {
            var vrfInputData = Data("jam_ticket_seal".utf8)
            vrfInputData.append(entropy.data)
            vrfInputData.append($0.attempt)
            let ticketId = verifier.ringVRFVerify(vrfInputData: vrfInputData, auxData: Data(), signature: $0.signature.data)
            return try Ticket(id: ticketId.get(), attempt: $0.attempt)
        }
    }
}
