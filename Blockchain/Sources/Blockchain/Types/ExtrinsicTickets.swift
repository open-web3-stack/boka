import ScaleCodec
import Utils

public struct ExtrinsicTickets: Sendable {
    public struct TicketItem: Sendable {
        public var attempt: TicketIndex
        public var signature: BandersnatchRintVRFProof

        public init(
            attempt: TicketIndex,
            signature: BandersnatchRintVRFProof
        ) {
            self.attempt = attempt
            self.signature = signature
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
    public typealias Config = ProtocolConfigRef
    public static func dummy(withConfig _: Config) -> ExtrinsicTickets {
        ExtrinsicTickets(tickets: [])
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
