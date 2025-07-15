import ArgumentParser
import Foundation
import Fuzzing
import Logging

extension Boka {
    struct Fuzz: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fuzz",
            abstract: "JAM Conformance Protocol",
            subcommands: [Target.self, Fuzzer.self]
        )
    }
}

extension Boka.Fuzz {
    struct Target: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run fuzzing target - waits for fuzzer connections"
        )

        @Option(help: "Unix socket path for fuzzing protocol")
        var socketPath: String = "/tmp/jam_conformance.sock"

        @Option(help: "JAM Protocol configuration preset, tiny or full")
        var config: String = "tiny"

        func run() async throws {
            let env = ProcessInfo.processInfo.environment
            LoggingSystem.bootstrap { label in
                var handler = StreamLogHandler.standardOutput(label: label)
                handler.logLevel = parseLevel(env["LOG_LEVEL"] ?? "") ?? .info
                return handler
            }

            let fuzzTarget = try FuzzingTarget(
                socketPath: socketPath,
                config: config
            )

            try await fuzzTarget.run()
        }
    }

    struct Fuzzer: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run fuzzing fuzzer - connects to targets"
        )

        @Option(help: "Unix socket path for fuzzing protocol.")
        var socketPath: String = "/tmp/jam_conformance.sock"

        @Option(help: "JAM Protocol configuration preset.")
        var config: String = "tiny"

        @Option(name: .long, help: "Random seed for deterministic testing. Default is random")
        var seed: UInt64 = .random(in: 0 ... UInt64.max)

        @Option(name: .long, help: "Number of blocks to process.")
        var blocks: Int = 100

        func run() async throws {
            let env = ProcessInfo.processInfo.environment
            LoggingSystem.bootstrap { label in
                var handler = StreamLogHandler.standardOutput(label: label)
                handler.logLevel = parseLevel(env["LOG_LEVEL"] ?? "") ?? .info
                return handler
            }

            let fuzzer = try FuzzingClient(
                socketPath: socketPath,
                config: config,
                seed: seed,
                blockCount: blocks
            )

            try await fuzzer.run()
        }
    }
}
