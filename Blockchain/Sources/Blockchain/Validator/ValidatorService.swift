import Foundation
import TracingUtils
import Utils

public final class ValidatorService: Sendable {
    private let schedulerService: ServiceBase2

    private let blockchain: Blockchain

    private let safrole: SafroleService
    private let safroleTicketPool: SafroleTicketPoolService
    private let blockAuthor: BlockAuthor
    private let dataAvailability: DataAvailability

    private let allServices: [Sendable]

    public init(
        blockchain: Blockchain,
        keystore: KeyStore,
        eventBus: EventBus,
        scheduler: Scheduler,
        dataProvider: BlockchainDataProvider,
        dataStore: DataStore
    ) async {
        self.blockchain = blockchain

        schedulerService = ServiceBase2(
            id: "ValidatorService",
            config: blockchain.config,
            eventBus: eventBus,
            scheduler: scheduler
        )

        safrole = await SafroleService(
            config: blockchain.config,
            eventBus: eventBus,
            keystore: keystore
        )

        safroleTicketPool = await SafroleTicketPoolService(
            config: blockchain.config,
            dataProvider: dataProvider,
            eventBus: eventBus
        )

        blockAuthor = await BlockAuthor(
            config: blockchain.config,
            dataProvider: dataProvider,
            eventBus: eventBus,
            keystore: keystore,
            scheduler: scheduler,
            safroleTicketPool: safroleTicketPool
        )

        dataAvailability = await DataAvailability(
            config: blockchain.config,
            eventBus: eventBus,
            scheduler: scheduler,
            dataProvider: dataProvider,
            dataStore: dataStore
        )

        allServices = [
            safrole,
            safroleTicketPool,
            blockAuthor,
            dataAvailability,
        ]
    }

    public func onSyncCompleted() async {
        for service in allServices {
            if let service = service as? OnSyncCompleted {
                await service.onSyncCompleted()
            }
        }

        schedulerService.scheduleForNextEpoch("ValidatorService.scheduleForNextEpoch") { [weak self] epoch in
            await self?.onBeforeEpoch(epoch: epoch)
        }
    }

    public func on(genesis: StateRef) async {
        for service in allServices {
            if let service = service as? OnGenesis {
                await service.on(genesis: genesis)
            }
        }

        let config = blockchain.config
        let timeProvider = schedulerService.timeProvider

        let nowTimeslot = timeProvider.getTime().timeToTimeslot(config: config)
        // schedule for current epoch
        let epoch = nowTimeslot.timeslotToEpochIndex(config: config)
        await onBeforeEpoch(epoch: epoch)
    }

    public func onBeforeEpoch(epoch: EpochIndex) async {
        await withSpan("ValidatorService.onBeforeEpoch", logger: schedulerService.logger) { _ in
            let config = blockchain.config

            let state = try await self.blockchain.dataProvider.getState(hash: blockchain.dataProvider.bestHead.hash)

            let timeslot = epoch.epochToTimeslotIndex(config: config)

            // simulate next block to determine the block authors for next epoch
            let res = try state.value.updateSafrole(
                config: config,
                slot: timeslot,
                entropy: Data32(),
                offenders: [],
                extrinsics: .dummy(config: config)
            )

            for service in allServices {
                if let service = service as? OnBeforeEpoch {
                    await service.onBeforeEpoch(epoch: epoch, safroleState: res.state)
                }
            }

            blockchain.publish(event: RuntimeEvents.BeforeEpochChange(epoch: epoch, state: res.state))
        }
    }
}
