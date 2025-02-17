import Utils

public enum RuntimeEvents {
    public struct BlockImported: Event {
        public let block: BlockRef
        public let state: StateRef
        public let parentState: StateRef

        public init(block: BlockRef, state: StateRef, parentState: StateRef) {
            self.block = block
            self.state = state
            self.parentState = parentState
        }
    }

    public struct BlockFinalized: Event {
        public let hash: Data32

        public init(hash: Data32) {
            self.hash = hash
        }
    }

    // New safrole ticket generated from SafroleService
    public struct SafroleTicketsGenerated: Event {
        public let epochIndex: EpochIndex
        public let items: [TicketItemAndOutput]
        public let publicKey: Bandersnatch.PublicKey

        public init(
            epochIndex: EpochIndex,
            items: [TicketItemAndOutput],
            publicKey: Bandersnatch.PublicKey
        ) {
            self.epochIndex = epochIndex
            self.items = items
            self.publicKey = publicKey
        }
    }

    // New safrole ticket received from network
    public struct SafroleTicketsReceived: Event {
        public let items: [ExtrinsicTickets.TicketItem]

        public init(items: [ExtrinsicTickets.TicketItem]) {
            self.items = items
        }
    }

    // New block authored by BlockAuthor service
    public struct BlockAuthored: Event {
        public let block: BlockRef
    }

    // New WorkPackagesReceived by Guaranteeing Service
    public struct WorkPackagesReceived: Event {
        public let items: [WorkPackage]
    }

    // WorkPackages Finalize by WorkPackages Service
    public struct WorkPackagesFinalized: Event {
        public let items: [WorkPackage]
    }

    // New WorkReportGenerated by Guaranteeing Service
    public struct WorkReportGenerated: Event {
        public let items: [WorkReport]
    }

    // New GuaranteeGenerated by Guaranteeing Service
    public struct GuaranteeGenerated: Event {
        public let items: [WorkPackage]
    }
}
