import Blockchain
import Node
import TracingUtils
import Utils

struct NodeDescription {
    let isValidator: Bool
    let devSeed: UInt32

    public init(isValidator: Bool = false, devSeed: UInt32 = 0) {
        self.isValidator = isValidator
        self.devSeed = devSeed
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
        // setupTestLogger()

        let timeProvider = MockTimeProvider(time: 1000)
        let scheduler = MockScheduler(timeProvider: timeProvider)
        var ret: [(Node, StoreMiddleware)] = []
        for desc in nodes {
            let storeMiddleware = StoreMiddleware()
            let eventBus = EventBus(eventMiddleware: .serial(Middleware(storeMiddleware), .noError), handlerMiddleware: .noError)
            let keystore = try await DevKeyStore(devKeysCount: 0)
            let keys = try await keystore.addDevKeys(seed: desc.devSeed)
            let nodeConfig = await Node.Config(
                rpc: nil,
                network: Network.Config(
                    role: desc.isValidator ? .validator : .builder,
                    listenAddress: NetAddr(address: "127.0.0.1:0")!,
                    key: keystore.get(Ed25519.self, publicKey: keys.ed25519)!
                ),
                peers: [],
                local: nodes.count == 1
            )
            let nodeCls = desc.isValidator ? ValidatorNode.self : Node.self
            let node = try await nodeCls.init(
                config: nodeConfig,
                genesis: genesis,
                eventBus: eventBus,
                keystore: keystore,
                scheduler: scheduler
            )
            ret.append((node, storeMiddleware))
        }

        // wait for the listeners to be ready
        try await Task.sleep(for: .milliseconds(500))

        for (from, to) in connections {
            let fromNode = ret[from].0
            let toNode = ret[to].0
            _ = try fromNode.network.network.connect(to: toNode.network.network.listenAddress(), role: .validator)
        }
        return (ret, scheduler)
    }
}