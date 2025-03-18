import Codec
import Foundation
import TracingUtils
import Utils

enum DataAvailabilityStore: String, Sendable {
    case imports
    case audits
}

public final class DataAvailability: ServiceBase2, @unchecked Sendable {
    private let dataProvider: BlockchainDataProvider
    private let dataStore: DataStore

    public init(
        config: ProtocolConfigRef,
        eventBus: EventBus,
        scheduler: Scheduler,
        dataProvider: BlockchainDataProvider,
        dataStore: DataStore
    ) async {
        self.dataProvider = dataProvider
        self.dataStore = dataStore

        super.init(id: "DataAvailability", config: config, eventBus: eventBus, scheduler: scheduler)

        scheduleForNextEpoch("BlockAuthor.scheduleForNextEpoch") { [weak self] epoch in
            await self?.purge(epoch: epoch)
        }
    }

    public func purge(epoch _: EpochIndex) async {
        // TODO: purge data
        // GP 14.3.1
        // Guarantors are required to erasure-code and distribute two data sets: one blob, the auditable work-package containing
        // the encoded work-package, extrinsic data and self-justifying imported segments which is placed in the short-term Audit
        // da store and a second set of exported-segments data together with the Paged-Proofs metadata. Items in the first store
        // are short-lived; assurers are expected to keep them only until finality of the block in which the availability of the work-
        // result’s work-package is assured. Items in the second, meanwhile, are long-lived and expected to be kept for a minimum
        // of 28 days (672 complete epochs) following the reporting of the work-report.
    }

    public func fetchSegment(
        segments: [WorkItem.ImportedDataSegment],
        segmentsRootMappings: SegmentsRootMappings? = nil
    ) async throws -> [Data4104] {
        try await dataStore.fetchSegment(segments: segments, segmentsRootMappings: segmentsRootMappings)
    }

    public func exportSegments(data: [Data4104], erasureRoot: Data32) async throws -> Data32 {
        let segmentRoot = Merklization.constantDepthMerklize(data.map(\.data))

        for (index, data) in data.enumerated() {
            try await dataStore.set(data: data, erasureRoot: erasureRoot, index: UInt16(index))
        }

        return segmentRoot
    }

    public func exportWorkpackageBundle(bundle: WorkPackageBundle) async throws -> (erasureRoot: Data32, length: DataLength) {
        // TODO: distribute workpackage bundle to audits DA
        // and correctly generate the erasure root

        // This is just a mock implementation
        let data = try JamEncoder.encode(bundle)
        let erasureRoot = data.blake2b256hash()

        return (erasureRoot, DataLength(data.count))
    }
}
