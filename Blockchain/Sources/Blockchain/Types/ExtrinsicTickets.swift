import ScaleCodec
import Utils

public struct ExtrinsicTickets {
    public struct TicketItem {
        public var ticketIndex: TicketIndex
        public var proof: BandersnatchRintVRFProof

        public init(
            ticketIndex: TicketIndex,
            proof: BandersnatchRintVRFProof
        ) {
            self.ticketIndex = ticketIndex
            self.proof = proof
        }
    }

    public var tickets: [TicketItem]

    public init(
        tickets: [TicketItem]
    ) {
        self.tickets = tickets
    }
}

extension ExtrinsicTickets: Dummy {
    public static var dummy: ExtrinsicTickets {
        ExtrinsicTickets(tickets: [])
    }
}

extension ExtrinsicTickets.TicketItem: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            ticketIndex: decoder.decode(),
            proof: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(ticketIndex)
        try encoder.encode(proof)
    }
}

extension ExtrinsicTickets: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            tickets: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(tickets)
    }
}
