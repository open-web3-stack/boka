import Utils

public struct Ticket: Sendable, Equatable, Codable {
    /// y
    public var id: Data32
    /// r
    public var attempt: TicketIndex
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
