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

    // When a work package is recived via CE133
    public struct WorkPackagesReceived: Event {
        public let coreIndex: CoreIndex
        public let workPackageRef: WorkPackageRef
        public let extrinsics: [Data]

        public init(coreIndex: CoreIndex, workPackageRef: WorkPackageRef, extrinsics: [Data]) {
            self.coreIndex = coreIndex
            self.workPackageRef = workPackageRef
            self.extrinsics = extrinsics
        }
    }

    // When a work package bundle is ready to shared via CE134
    public struct WorkPackageBundleReady: Event {
        public let coreIndex: CoreIndex
        public let bundle: WorkPackageBundle
        public let segmentsRootMappings: SegmentsRootMappings

        public init(
            coreIndex: CoreIndex,
            bundle: WorkPackageBundle,
            segmentsRootMappings: SegmentsRootMappings
        ) {
            self.coreIndex = coreIndex
            self.bundle = bundle
            self.segmentsRootMappings = segmentsRootMappings
        }
    }

    // When a work package will be shared via CE134
    public struct ShareWorkPackage: Event {
        public let coreIndex: CoreIndex
        public let workPackage: WorkPackageRef
        public let extrinsics: [Data]

        public init(coreIndex: CoreIndex, workPackage: WorkPackageRef, extrinsics: [Data]) {
            self.coreIndex = coreIndex
            self.workPackage = workPackage
            self.extrinsics = extrinsics
        }
    }

    // When a work package bundle is recived via CE134
    public struct WorkPackageBundleRecived: Event {
        public let workPackageHash: Data32
        public let edd25519Signature: Data64
        public init(workPackageHash: Data32, edd25519Signature: Data64) {
            self.workPackageHash = workPackageHash
            self.edd25519Signature = edd25519Signature
        }
    }

    // When a work report is generated and ready to be distrubuted via CE135
    public struct WorkReportGenerated: Event {
        public let item: WorkReport
        public let signature: Ed25519Signature
    }
}
