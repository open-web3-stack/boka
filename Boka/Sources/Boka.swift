// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import ArgumentParser
import Node
import ServiceLifecycle
import TracingUtils
import Utils

@main
struct Boka: AsyncParsableCommand {
    mutating func run() async throws {
        let services = try await Tracing.bootstrap("Boka")
        let logger = Logger(label: "boka")

        logger.info("Starting Boka...")

        let config = Node.Config(rpc: RPCConfig(listenAddress: "127.0.0.1", port: 9955), protocol: .dev)
        let eventBus = EventBus(
            eventMiddleware: .serial(
                .log(logger: Logger(label: "EventBus")),
                .tracing(prefix: "EventBusEvent")
            ),
            handlerMiddleware: .tracing(prefix: "Handler")
        )
        do {
            let node = try await Node(genesis: .dev, config: config, eventBus: eventBus)

            for service in services {
                Task {
                    try await service.run()
                }
            }

            try await node.wait()
        }

        logger.info("Exiting...")
    }
}
