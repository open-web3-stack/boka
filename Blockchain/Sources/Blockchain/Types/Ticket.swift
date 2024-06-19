import ScaleCodec
import Utils

public struct Ticket {
    public var identifier: H256
    public var entryIndex: TicketIndex
}

extension Ticket: Dummy {
    public static var dummy: Ticket {
        Ticket(identifier: H256(), entryIndex: 0)
    }
}

extension Ticket: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            identifier: decoder.decode(),
            entryIndex: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(identifier)
        try encoder.encode(entryIndex)
    }
}
