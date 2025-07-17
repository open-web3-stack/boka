import ArgumentParser
import Blockchain
import Foundation
import Node
import ServiceLifecycle
import TracingUtils
import Utils

extension Genesis: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        if let preset = GenesisPreset(rawValue: argument) {
            self = .preset(preset)
        } else {
            self = .file(path: argument)
        }
    }
}

extension NetAddr: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(address: argument)
    }
}

enum MaybeEnabled<T: ExpressibleByArgument>: ExpressibleByArgument {
    case enabled(T)
    case disabled

    init?(argument: String) {
        if argument.lowercased() == "no" {
            self = .disabled
        } else {
            guard let argument = T(argument: argument) else {
                return nil
            }
            self = .enabled(argument)
        }
    }

    var asOptional: T? {
        switch self {
        case let .enabled(value):
            value
        case .disabled:
            nil
        }
    }
}

@main
struct Boka: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "JAM built with Swift",
        version: "0.0.1",
        subcommands: [Generate.self, Fuzz.self]
    )

    @Option(name: .shortAndLong, help: "Base path to database files.")
    var basePath: String?

    @Option(name: .long, help: "A preset config or path to chain config file.")
    var chain: Genesis = .preset(.minimal)

    @Option(name: .long, help: "Listen address for RPC server. Pass 'no' to disable RPC server. Default to 127.0.0.1:9955.")
    var rpc: MaybeEnabled<NetAddr> = .enabled(NetAddr(address: "127.0.0.1:9955")!)

    @Option(name: .long, help: "Listen address for P2P protocol.")
    var p2p: NetAddr = .init(address: "127.0.0.1:0")!

    @Option(name: .long, help: "Specify peer P2P addresses.")
    var peers: [NetAddr] = []

    @Flag(name: .long, help: "Run as a validator.")
    var validator = false

    @Option(name: .long, help: "Listen address for operator RPC server. Pass 'false' to disable operator RPC server. Default to false.")
    var operatorRpc: NetAddr?

    @Option(name: .long, help: "For development only. Seed for validator keys.")
    var devSeed: UInt32?

    @Option(name: .long, help: "Node name. For telemetry only.")
    var name: String?

    @Flag(name: .long, help: "Enable local mode, whereas peers are not expected.")
    var local: Bool = false

    @Flag(name: .long, help: "Enable dev mode. This is equivalent to --local --validator")
    var dev: Bool = false

    mutating func run() async throws {
        let services = try await Tracing.bootstrap("Boka", loggerOnly: true)
        for service in services {
            Task {
                try await service.run()
            }
        }

        let logger = Logger(label: "cli")

        logger.info("Starting Boka.")

        logger.info("Chain: \(chain)")

        if dev {
            local = true
            validator = true
            logger.info("Dev mode enabled. Enabling local and validator.")
        }

        if local {
            logger.info("Local mode enabled.")
        }

        if let name {
            logger.info("Node name: \(name)")
        }

        let database: Database = basePath.map {
            var path = URL(fileURLWithPath: $0)
            path.append(path: "db")
            return .rocksDB(path: path)
        } ?? .inMemory

        logger.info("Peers: \(peers)")

        if validator {
            logger.info("Running as validator")
        } else {
            logger.info("Running as fullnode")
        }

        if let operatorRpc {
            logger.info("Operator RPC listen address: \(operatorRpc)")
        }

        let rpcConfig = rpc.asOptional.map { addr -> RPCConfig in
            let (address, port) = addr.getAddressAndPort()
            return RPCConfig(listenAddress: address, port: Int(port))
        }

        let keysotreType: KeyStoreType = basePath.map {
            let path = URL(fileURLWithPath: $0)
            return .file(path: path)
        } ?? .inMemory

        let keystore: KeyStore = try keysotreType.getStore()

        let networkKey: Ed25519.SecretKey = try await {
            if let devSeed {
                let key = try await keystore.addDevKeys(seed: devSeed)
                return await keystore.get(Ed25519.self, publicKey: key.ed25519)!
            } else {
                return try await keystore.generate(Ed25519.self)
            }
        }()

        logger.info("Network key: \(networkKey.publicKey.data.toHexString())")
        let networkConfig = NetworkConfig(
            role: validator ? .validator : .builder,
            listenAddress: p2p,
            key: networkKey
        )

        let eventBus = EventBus(
            eventMiddleware: .serial(
                .log(logger: Logger(label: "EventBus")),
                .tracing(prefix: "EventBusEvent")
            ),
            handlerMiddleware: .tracing(prefix: "Handler")
        )

        let config = Config(
            rpc: rpcConfig,
            network: networkConfig,
            peers: peers,
            local: local,
            name: name,
            database: database,
            keystoreType: keysotreType
        )

        let node: Node = if validator {
            try await ValidatorNode(
                config: config, genesis: chain, eventBus: eventBus, keystore: keystore
            )
        } else {
            try await Node(
                config: config, genesis: chain, eventBus: eventBus, keystore: keystore
            )
        }

        try await node.wait()

        logger.notice("Shutting down...")
    }
}
