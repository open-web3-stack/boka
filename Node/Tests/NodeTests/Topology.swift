import Blockchain
import Node
import TracingUtils
import Utils

struct NodeDescription {
    let isValidator: Bool
    let devSeed: UInt32
    let database: Database

    public init(isValidator: Bool = false, devSeed: UInt32 = 0, database: Database = .inMemory) {
        self.isValidator = isValidator
        self.devSeed = devSeed
        self.database = database
    }
}

struct Topology {
    let nodes: [NodeDescription]
    let connections: [(Int, Int)]

    init(nodes: [NodeDescription], connections: [(Int, Int)] = []) {
        self.nodes = nodes
        self.connections = connections
    }

    func build(genesis: Genesis) async throws -> ([(Node, StoreMiddleware)], MockScheduler) {
        let timeProvider = MockTimeProvider(time: 1000)
        let scheduler = MockScheduler(timeProvider: timeProvider)
        let logger = Logger(label: "TopologyTest")
        var ret: [(Node, StoreMiddleware)] = []
        for desc in nodes {
            let storeMiddleware = StoreMiddleware()
            let logMiddleware = LogMiddleware(logger: logger, propagateError: true)
            let eventBus = EventBus(
                eventMiddleware: .serial(Middleware(storeMiddleware), Middleware(logMiddleware)),
                handlerMiddleware: Middleware(logMiddleware)
            )
            let keystore = try await DevKeyStore(devKeysCount: 0)
            let keys = try await keystore.addDevKeys(seed: desc.devSeed)
            let nodeConfig = await Config(
                rpc: nil,
                network: Network.Config(
                    role: desc.isValidator ? .validator : .builder,
                    listenAddress: NetAddr(address: "127.0.0.1:0")!,
                    key: keystore.get(Ed25519.self, publicKey: keys.ed25519)!
                ),
                peers: [],
                local: nodes.count == 1,
                database: desc.database
            )
            let nodeCls = desc.isValidator ? ValidatorNode.self : Node.self
            let node = try await nodeCls.init(
                config: nodeConfig,
                genesis: genesis,
                eventBus: eventBus,
                keystore: keystore,
                scheduler: scheduler
            )
            await storeMiddleware.wait()
            ret.append((node, storeMiddleware))
        }

        // wait for the listeners to be ready
        try await Task.sleep(for: .milliseconds(500))

        for (from, to) in connections {
            let fromNode = ret[from].0
            let toNode = ret[to].0
            let conn = try fromNode.network.network.connect(to: toNode.network.network.listenAddress(), role: .validator)
            try? await conn.ready()
        }
        return (ret, scheduler)
    }
}
