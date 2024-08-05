// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import ArgumentParser
import Node

@main
struct Boka: ParsableCommand {
    mutating func run() async throws {
        let node = try await Node(genesis: .dev, config: .dev)
        node.sayHello()
    }
}
