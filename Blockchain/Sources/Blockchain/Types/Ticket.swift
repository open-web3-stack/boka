import ScaleCodec
import Utils

public struct Ticket: Sendable, Equatable {
    public var id: Data32
    public var attempt: TicketIndex
}

extension Ticket: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> Ticket {
        Ticket(id: Data32(), attempt: 0)
    }
}

extension Ticket: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            id: decoder.decode(),
            attempt: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(id)
        try encoder.encode(attempt)
    }
}
