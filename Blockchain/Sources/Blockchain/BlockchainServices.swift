import Foundation
import Utils

// For testing only
public class BlockchainServices: @unchecked Sendable {
    public let config: ProtocolConfigRef
    public let timeProvider: MockTimeProvider
    public let dataProvider: BlockchainDataProvider
    public let dataStore: DataStore
    public let eventBus: EventBus
    public let scheduler: MockScheduler
    public let keystore: DevKeyStore
    public let storeMiddleware: StoreMiddleware
    public let genesisBlock: BlockRef
    public let genesisState: StateRef

    private var _blockchain: Blockchain?
    private weak var _blockchainRef: Blockchain?

    private var _blockAuthor: BlockAuthor?
    private weak var _blockAuthorRef: BlockAuthor?

    private var _guaranteeingService: GuaranteeingService?
    private weak var _guaranteeingServiceRef: GuaranteeingService?

    private let schedulerService: ServiceBase2

    public init(
        config: ProtocolConfigRef = .dev,
        timeProvider: MockTimeProvider = MockTimeProvider(time: 988),
        keysCount: Int = 12
    ) async {
        self.config = config
        self.timeProvider = timeProvider

        let (genesisState, genesisBlock) = try! State.devGenesis(config: config)
        self.genesisBlock = genesisBlock
        self.genesisState = genesisState
        dataProvider = try! await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))
        let dataStoreBackend = InMemoryDataStoreBackend()
        dataStore = DataStore(dataStoreBackend, dataStoreBackend)

        storeMiddleware = StoreMiddleware()
        eventBus = EventBus(eventMiddleware: .serial(Middleware(storeMiddleware), .noError), handlerMiddleware: .noError)

        scheduler = MockScheduler(timeProvider: timeProvider)

        keystore = try! await DevKeyStore(devKeysCount: keysCount)

        schedulerService = ServiceBase2(
            id: "BlockchainServices.schedulerService",
            config: config,
            eventBus: eventBus,
            scheduler: scheduler
        )

        schedulerService.scheduleForNextEpoch("BlockchainServices.scheduleForNextEpoch") { [weak self] epoch in
            await self?.onBeforeEpoch(epoch: epoch)
        }
    }

    deinit {
        _blockchain = nil
        _blockAuthor = nil
        _guaranteeingService = nil

        if let _blockchainRef {
            fatalError("BlockchainServices: blockchain still alive. retain count: \(_getRetainCount(_blockchainRef))")
        }

        if let _blockAuthorRef {
            fatalError("BlockchainServices: blockAuthor still alive. retain count: \(_getRetainCount(_blockAuthorRef))")
        }

        if let _guaranteeingServiceRef {
            fatalError("BlockchainServices: guaranteeingService still alive. retain count: \(_getRetainCount(_guaranteeingServiceRef))")
        }
    }

    public var blockchain: Blockchain {
        get async {
            if let _blockchain {
                return _blockchain
            }
            _blockchain = try! await Blockchain(
                config: config,
                dataProvider: dataProvider,
                timeProvider: timeProvider,
                eventBus: eventBus
            )
            _blockchainRef = _blockchain
            return _blockchain!
        }
    }

    public var blockAuthor: BlockAuthor {
        get async {
            if let _blockAuthor {
                return _blockAuthor
            }
            _blockAuthor = await BlockAuthor(
                config: config,
                dataProvider: dataProvider,
                eventBus: eventBus,
                keystore: keystore,
                scheduler: scheduler,
                safroleTicketPool: SafroleTicketPoolService(config: config, dataProvider: dataProvider, eventBus: eventBus)
            )
            _blockAuthorRef = _blockAuthor

            await callOnBeforeEpoch(epoch: nil, targets: [_blockAuthor!])

            return _blockAuthor!
        }
    }

    public var guaranteeingService: GuaranteeingService {
        get async {
            if let _guaranteeingService {
                return _guaranteeingService
            }
            _guaranteeingService = await GuaranteeingService(
                config: config,
                eventBus: eventBus,
                scheduler: scheduler,
                dataProvider: dataProvider,
                keystore: keystore,
                dataStore: dataStore
            )
            _guaranteeingServiceRef = _guaranteeingService

            await _guaranteeingService!.onSyncCompleted()

            await callOnBeforeEpoch(epoch: nil, targets: [_guaranteeingService!])

            return _guaranteeingService!
        }
    }

    private nonisolated func callOnBeforeEpoch(epoch: EpochIndex?, targets: [OnBeforeEpoch]) async {
        do {
            let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)

            let (timeslot, epoch) = if let epoch {
                (epoch.epochToTimeslotIndex(config: config), epoch)
            } else {
                {
                    let timeslot = timeProvider.getTime().timeToTimeslot(config: config)
                    return (timeslot, timeslot.timeslotToEpochIndex(config: config))
                }()
            }

            // simulate next block to determine the block authors for next epoch
            let res = try state.value.updateSafrole(
                config: config,
                slot: timeslot,
                entropy: Data32(),
                offenders: [],
                extrinsics: .dummy(config: config)
            )

            for service in targets {
                await service.onBeforeEpoch(epoch: epoch, safroleState: res.state)
            }

            await eventBus.publish(RuntimeEvents.BeforeEpochChange(epoch: epoch, state: res.state))
        } catch {
            fatalError("onBeforeEpoch failed: \(error)")
        }
    }

    private func onBeforeEpoch(epoch: EpochIndex?) async {
        var targets: [OnBeforeEpoch] = []
        if let blockAuthor = _blockAuthor {
            targets.append(blockAuthor)
        }
        if let guaranteeingService = _guaranteeingService {
            targets.append(guaranteeingService)
        }

        await callOnBeforeEpoch(epoch: epoch, targets: targets)
    }

    public nonisolated func publishOnBeforeEpochEvent() async {
        do {
            let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)

            let timeslot = timeProvider.getTime().timeToTimeslot(config: config)
            let epoch = timeslot.timeslotToEpochIndex(config: config)

            // simulate next block to determine the block authors for next epoch
            let res = try state.value.updateSafrole(
                config: config,
                slot: timeslot,
                entropy: Data32(),
                offenders: [],
                extrinsics: .dummy(config: config)
            )

            await eventBus.publish(RuntimeEvents.BeforeEpochChange(epoch: epoch, state: res.state))
        } catch {
            fatalError("onBeforeEpoch failed: \(error)")
        }
    }
}
