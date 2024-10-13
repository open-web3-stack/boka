// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import ArgumentParser
import Blockchain
import Foundation
import Node
import ServiceLifecycle
import TracingUtils
import Utils

@main
struct Boka: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A command-line tool for Boka.",
        version: "1.0.0"
    )

    @Option(name: [.customShort("d"), .long], help: "Base path to database files.")
    var basePath: String?

    @Option(name: [.customShort("c"), .long], help: "Path to chain spec file.")
    var chain: String?

    @Option(name: [.customShort("f"), .long], help: "Path to config file.")
    var configFile: String?

    @Option(
        name: [.customLong("rpc"), .long],
        help:
        "Listen address for RPC server. Pass 'false' to disable RPC server. Default to 127.0.0.1:9955."
    )
    var rpcListenAddress: String = "127.0.0.1:9955"

    @Option(name: [.customLong("p2p"), .long], help: "Listen address for P2P protocol.")
    var p2pListenAddress: String?

    @Option(
        name: [.customLong("peers"), .long], parsing: .upToNextOption,
        help: "Specify peer P2P addresses."
    )
    var p2pPeers: [String] = []

    @Flag(name: .long, help: "Run as a validator.")
    var validator: Bool = false

    @Option(
        name: [.customLong("operator-rpc"), .long],
        help:
        "Listen address for operator RPC server. Pass 'false' to disable operator RPC server. Default to false."
    )
    var operatorRpcListenAddress: String = "false"

    @Option(name: .long, help: "For development only. Seed for validator keys.")
    var devSeed: String?

    mutating func run() async throws {
        let logger = Logger(label: "boka")

        if let basePath {
            logger.info("Base Path: \(basePath)")
        }
        if let chain {
            logger.info("Chain: \(chain)")
        }
        if let configFile {
            logger.info("Config File: \(configFile)")
        }

        logger.info("RPC Listen Address: \(rpcListenAddress)")

        if let p2pListenAddress {
            logger.info("P2P Listen Address: \(p2pListenAddress)")
        }
        if rpcListenAddress.lowercased() == "false" {
            logger.warning("TODO: RPC server is disabled")
            rpcListenAddress = "127.0.0.1:9955"
        }
        let (rpcAddress, rpcPort) = try Regexs.parseAddress(rpcListenAddress)

        if !p2pPeers.isEmpty {
            logger.info("P2P Peers: \(p2pPeers.joined(separator: ", "))")
        }
        logger.info("Validator: \(validator ? "Enabled" : "Disabled")")

        if operatorRpcListenAddress.lowercased() == "false" {
            logger.warning("TODO:  Operator RPC server is disabled")
        } else {
            logger.info("Operator RPC Listen Address: \(operatorRpcListenAddress)")
        }

        if let devSeed {
            logger.info("Dev Seed: \(devSeed)")
        }

        let services = try await Tracing.bootstrap("Boka", loggerOnly: true)

        logger.info("Starting Boka...")

        let config = Node.Config(
            rpc: RPCConfig(listenAddress: rpcAddress, port: rpcPort)
        )
        let eventBus = EventBus(
            eventMiddleware: .serial(
                .log(logger: Logger(label: "EventBus")),
                .tracing(prefix: "EventBusEvent")
            ),
            handlerMiddleware: .tracing(prefix: "Handler")
        )
        let keystore = try await DevKeyStore()
        do {
            logger.info("Starting ValidatorNode...")
            let node = try await ValidatorNode(
                genesis: .dev, config: config, eventBus: eventBus, keystore: keystore
            )
            logger.info("ValidatorNode started successfully.")

            for service in services {
                Task {
                    try await service.run()
                }
            }
            try await node.wait()
        } catch {
            logger.error("Failed to start ValidatorNode: \(error.localizedDescription)")
            throw error
        }
        logger.info("Exiting...")
    }
}
