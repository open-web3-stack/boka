// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import ArgumentParser
import Node
import TracingUtils

@main
struct Boka: ParsableCommand {
    mutating func run() async throws {
        let services = try await Tracing.bootstrap("Boka")
        let node = try await Node(genesis: .dev, config: .dev)
        node.sayHello()

        let config = ServiceGroupConfiguration(services: services, logger: Logger(label: "boka"))
        let serviceGroup = ServiceGroup(configuration: config)

        try await serviceGroup.run()
    }
}
