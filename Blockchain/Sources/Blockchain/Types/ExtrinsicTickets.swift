import Utils

public struct ExtrinsicTickets {
    public var tickets: [
        (ticketIndex: TicketIndex, proof: BandersnatchRintVRFProof)
    ]

    public init(
        tickets: [(ticketIndex: TicketIndex, proof: BandersnatchRintVRFProof)]
    ) {
        self.tickets = tickets
    }
}

extension ExtrinsicTickets: Dummy {
    public static var dummy: ExtrinsicTickets {
        ExtrinsicTickets(tickets: [])
    }
}
