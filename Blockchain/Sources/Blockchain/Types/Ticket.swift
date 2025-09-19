import Codec
import Utils

public struct Ticket: @unchecked Sendable, Equatable, Codable {
    // y
    public var id: Data32
    // r
    @CodingAs<Compact<TicketIndex>> public var attempt: TicketIndex

    public static func == (lhs: Ticket, rhs: Ticket) -> Bool {
        lhs.id == rhs.id && lhs.attempt == rhs.attempt
    }
}

extension Ticket: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> Ticket {
        Ticket(id: Data32(), attempt: 0)
    }
}

extension Ticket: Comparable {
    public static func < (lhs: Ticket, rhs: Ticket) -> Bool {
        (lhs.id, lhs.attempt) < (rhs.id, rhs.attempt)
    }
}
