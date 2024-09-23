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

    public struct NewSafroleTickets: Event {
        public let items: [ExtrinsicTickets.TicketItem]
    }
}
