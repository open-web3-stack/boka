import Blockchain
import ConsoleKit
import Foundation
import Node
import ServiceLifecycle
import TracingUtils
import Utils

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

        if signature.version {
            context.console.info("Boka version 1.0.0")
            return
        }

        // Handle other options and flags
        if let basePath = signature.basePath {
            context.console.info("Base path: \(basePath)")
        }

        if let p2p = signature.p2p {
            context.console.info("P2P listen address: \(p2p)")
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

        if let devSeed = signature.devSeed {
            context.console.info("Dev seed: \(devSeed)")
        }

        var rpcListenAddress = "127.0.0.1:9955"
        if let rpc = signature.rpc {
            if rpc.lowercased() == "false" {
                context.console.warning("RPC server is disabled")
            } else {
                rpcListenAddress = rpc
            }
            context.console.info("RPC listen address: \(rpc)")
        }

        let (rpcAddress, rpcPort) = try Regexs.parseAddress(rpcListenAddress)
        let services = try await Tracing.bootstrap("Boka", loggerOnly: true)
        let config = Node.Config(rpc: RPCConfig(listenAddress: rpcAddress, port: rpcPort))
        let eventBus = EventBus(
            eventMiddleware: .serial(
                .log(logger: Logger(label: "EventBus")),
                .tracing(prefix: "EventBusEvent")
            ),
            handlerMiddleware: .tracing(prefix: "Handler")
        )
        let keystore = try await DevKeyStore()
        var genesis: Genesis = .dev
        if let configFile = signature.configFile {
            context.console.info("Config file: \(configFile)")
            genesis = .file(path: configFile)
        }
        let node: ValidatorNode = try await ValidatorNode(
            genesis: genesis, config: config, eventBus: eventBus, keystore: keystore
        )
        for service in services {
            Task {
                try await service.run()
            }
        }
        try await node.wait()
    }
}
