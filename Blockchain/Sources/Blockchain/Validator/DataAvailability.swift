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
    }
}
