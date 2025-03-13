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

    // Received new work package submission via RPC
    public struct WorkPackagesSubmitted: Event {
        public let coreIndex: CoreIndex
        public let workPackage: WorkPackageRef
        public let extrinsics: [Data]

        public init(coreIndex: CoreIndex, workPackage: WorkPackageRef, extrinsics: [Data]) {
            self.coreIndex = coreIndex
            self.workPackage = workPackage
            self.extrinsics = extrinsics
        }
    }

    // When a work package is received via CE133
    public struct WorkPackagesReceived: Event {
        public let coreIndex: CoreIndex
        public let workPackage: WorkPackageRef
        public let extrinsics: [Data]

        public init(coreIndex: CoreIndex, workPackage: WorkPackageRef, extrinsics: [Data]) {
            self.coreIndex = coreIndex
            self.workPackage = workPackage
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

    // When a work package bundle is recived via CE134
    public struct WorkPackageBundleRecived: Event {
        public let coreIndex: CoreIndex
        public let segmentsRootMappings: SegmentsRootMappings
        public let bundle: WorkPackageBundle

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

    // A guaranteed work-report ready for distribution via CE135.
    public struct WorkReportGenerated: Event {
        public let workReport: WorkReport
        public let slot: UInt32
        public var signatures: [ValidatorSignature]

        public init(
            workReport: WorkReport,
            slot: UInt32,
            signatures: [ValidatorSignature]
        ) {
            self.workReport = workReport
            self.slot = slot
            self.signatures = signatures
        }
    }

    // When a work report is received via CE135
    public struct WorkReportReceived: Event {
        public let workReport: WorkReport
        public let slot: UInt32
        public var signatures: [ValidatorSignature]

        public init(
            workReport: WorkReport,
            slot: UInt32,
            signatures: [ValidatorSignature]
        ) {
            self.workReport = workReport
            self.slot = slot
            self.signatures = signatures
        }
    }
}
