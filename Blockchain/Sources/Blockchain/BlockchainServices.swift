import Foundation
import Utils

// For testing only
public class BlockchainServices {
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
    }

    deinit {
        _blockchain = nil
        _blockAuthor = nil

        if let _blockchainRef {
            fatalError("BlockchainServices: blockchain still alive. retain count: \(_getRetainCount(_blockchainRef))")
        }

        if let _blockAuthorRef {
            fatalError("BlockchainServices: blockAuthor still alive. retain count: \(_getRetainCount(_blockAuthorRef))")
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
                extrinsicPool: ExtrinsicPoolService(config: config, dataProvider: dataProvider, eventBus: eventBus)
            )
            _blockAuthorRef = _blockAuthor
            return _blockAuthor!
        }
    }
}
