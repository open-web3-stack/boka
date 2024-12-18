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

    public func fetchSegment(root _: Data32, index _: UInt16) async throws -> Data? {
        // TODO: fetch segment
        nil
    }

    public func exportSegments(data _: [Data]) async throws {
        // TODO: export segments
    }

    public func distributeWorkpackageBundle(bundle _: WorkPackageBundle) async throws {
        // TODO: distribute workpackage bundle to audits DA
    }
}
