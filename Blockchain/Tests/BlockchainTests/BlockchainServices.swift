import Blockchain
import Utils

struct BlockchainServices {
    let config: ProtocolConfigRef
    let timeProvider: MockTimeProvider
    let dataProvider: BlockchainDataProvider
    let eventBus: EventBus
    let scheduler: MockScheduler
    let keystore: KeyStore
    let storeMiddleware: StoreMiddleware
    let blockchain: Blockchain
    let genesisBlock: BlockRef
    let genesisState: StateRef

    init(
        config: ProtocolConfigRef = .dev,
        timeProvider: MockTimeProvider = MockTimeProvider(time: 988)
    ) async throws {
        self.config = config
        self.timeProvider = timeProvider

        let (genesisState, genesisBlock) = try State.devGenesis(config: config)
        self.genesisBlock = genesisBlock
        self.genesisState = genesisState
        dataProvider = try await BlockchainDataProvider(InMemoryDataProvider(genesisState: genesisState, genesisBlock: genesisBlock))

        storeMiddleware = StoreMiddleware()
        eventBus = EventBus(eventMiddleware: .serial(Middleware(storeMiddleware), .noError), handlerMiddleware: .noError)

        scheduler = MockScheduler(timeProvider: timeProvider)

        keystore = try await DevKeyStore()

        blockchain = try await Blockchain(
            config: config,
            dataProvider: dataProvider,
            timeProvider: timeProvider,
            eventBus: eventBus
        )
    }
}
