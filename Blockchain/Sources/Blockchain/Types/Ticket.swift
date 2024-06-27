import ScaleCodec
import Utils

public struct Ticket: Sendable {
    public var identifier: H256
    public var entryIndex: TicketIndex
}

extension Ticket: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(withConfig _: Config) -> Ticket {
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
