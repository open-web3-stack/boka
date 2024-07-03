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
