import Blockchain
import ConsoleKit
import Foundation
import Node
import ServiceLifecycle
import TracingUtils
import Utils

enum InvalidArgumentError: Error {
    case invalidArgument(String)
}

struct Boka: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "base-path", short: "d", help: "Base path to database files.")
        var basePath: String?

        @Option(name: "chain", short: "c", help: "Path to chain spec file.")
        var chain: String?

        @Option(name: "config-file", short: "f", help: "Path to config file.")
        var configFile: String?

        @Option(
            name: "rpc",
            help:
            "Listen address for RPC server. Pass 'false' to disable RPC server. Default to 127.0.0.1:9955."
        )
        var rpc: String?

        @Option(name: "p2p", help: "Listen address for P2P protocol.")
        var p2p: String?

        @Option(name: "peers", help: "Specify peer P2P addresses separated by commas.")
        var peers: String?

        @Flag(name: "validator", help: "Run as a validator.")
        var validator: Bool

        @Option(
            name: "operator-rpc",
            help:
            "Listen address for operator RPC server. Pass 'false' to disable operator RPC server. Default to false."
        )
        var operatorRpc: String?

        @Option(name: "dev-seed", help: "For development only. Seed for validator keys.")
        var devSeed: String?

        @Flag(name: "version", help: "Show the version.")
        var version: Bool

        @Flag(name: "help", short: "h", help: "Show help information.")
        var help: Bool
    }

    var help: String {
        "A command-line tool for Boka."
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        if signature.help {
            context.console.info(help)
            return
        }
        // TODO: fix version number issue #168
        if signature.version {
            context.console.info("Boka version 1.0.0")
            return
        }

        let services = try await Tracing.bootstrap("Boka", loggerOnly: true)
        for service in services {
            Task {
                try await service.run()
            }
        }

        // Handle other options and flags
        if let basePath = signature.basePath {
            context.console.info("Base path: \(basePath)")
        }

        if let peers = signature.peers {
            let peerList = peers.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            context.console.info("Peers: \(peerList.joined(separator: ", "))")
        }

        if signature.validator {
            context.console.info("Running as validator")
        }

        if let operatorRpc = signature.operatorRpc {
            context.console.info("Operator RPC listen address: \(operatorRpc)")
        }

        var rpcListenAddress = NetAddr(ipAddress: "127.0.0.1", port: 9955)
        if let rpc = signature.rpc {
            if rpc.lowercased() == "false" {
                context.console.info("RPC server is disabled")
                rpcListenAddress = nil
            } else {
                if let addr = NetAddr(address: rpc) {
                    rpcListenAddress = addr
                } else {
                    throw InvalidArgumentError.invalidArgument("Invalid RPC address")
                }
            }
        }

        let rpcConfig = rpcListenAddress.map { rpcListenAddress in
            let (rpcAddress, rpcPort) = rpcListenAddress.getAddressAndPort()
            return RPCConfig(listenAddress: rpcAddress, port: Int(rpcPort))
        }

        var p2pListenAddress = NetAddr(ipAddress: "127.0.0.1", port: 19955)!
        if let p2p = signature.p2p {
            if let addr = NetAddr(address: p2p) {
                p2pListenAddress = addr
            } else {
                throw InvalidArgumentError.invalidArgument("Invalid P2P address")
            }
        }

        let keystore = try await DevKeyStore()

        var devKey: KeySet?
        let networkKey: Ed25519.SecretKey
        if let devSeed = signature.devSeed {
            guard let val = UInt32(devSeed) else {
                throw InvalidArgumentError.invalidArgument("devSeed is not a valid hex string")
            }
            devKey = try await keystore.addDevKeys(seed: val)
            networkKey = await keystore.get(Ed25519.self, publicKey: devKey!.ed25519)!
        } else {
            // TODO: only generate network key if keystore is empty
            networkKey = try await keystore.generate(Ed25519.self)
        }

        let networkConfig = NetworkConfig(
            mode: signature.validator ? .validator : .builder,
            listenAddress: p2pListenAddress,
            key: networkKey
        )

        let eventBus = EventBus(
            eventMiddleware: .serial(
                .log(logger: Logger(label: "EventBus")),
                .tracing(prefix: "EventBusEvent")
            ),
            handlerMiddleware: .tracing(prefix: "Handler")
        )

        var genesis: Genesis = .dev
        if let configFile = signature.configFile {
            context.console.info("Config file: \(configFile)")
            genesis = .file(path: configFile)
        }

        let config = Node.Config(rpc: rpcConfig, network: networkConfig)

        let node: Node = if signature.validator {
            try await ValidatorNode(
                config: config, genesis: genesis, eventBus: eventBus, keystore: keystore
            )
        } else {
            try await Node(
                config: config, genesis: genesis, eventBus: eventBus, keystore: keystore
            )
        }

        try await node.wait()

        console.info("Shutting down...")
    }
}
