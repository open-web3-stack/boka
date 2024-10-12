import Utils

public enum RuntimeEvents {
    public struct BlockImported: Event {
        public let block: BlockRef
        public let state: StateRef
        public let parentState: StateRef
    }

    public struct BlockFinalized: Event {
        public let hash: Data32
    }

    // New safrole ticket generated from SafroleService
    public struct SafroleTicketsGenerated: Event {
        public let items: [TicketItemAndOutput]
        public let publicKey: Bandersnatch.PublicKey
    }

    // New safrole ticket received from network
    public struct SafroleTicketsReceived: Event {
        public let items: [ExtrinsicTickets.TicketItem]
    }

    // New block authored by BlockAuthor service
    public struct BlockAuthored: Event {
        public let block: BlockRef
    }
}
