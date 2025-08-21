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
    enum JamConfig: String, CaseIterable, ExpressibleByArgument {
        case tiny
        case full
    }

    struct Target: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run fuzzing target - waits for fuzzer connections"
        )

        @Option(help: "Unix socket path for fuzzing protocol")
        var socketPath: String = "/tmp/jam_conformance.sock"

        @Option(help: "JAM Protocol configuration preset")
        var config: JamConfig = .tiny

        func run() async throws {
            let env = ProcessInfo.processInfo.environment
            LoggingSystem.bootstrap { label in
                var handler = StreamLogHandler.standardOutput(label: label)
                handler.logLevel = parseLevel(env["LOG_LEVEL"] ?? "") ?? .info
                return handler
            }

            let fuzzTarget = try FuzzingTarget(
                socketPath: socketPath,
                config: config.rawValue
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
        var config: JamConfig = .tiny

        @Option(name: .long, help: "Random seed for deterministic testing. Default is random.")
        var seed: UInt64 = .random(in: 0 ... UInt64.max)

        @Option(name: .long, help: "Number of blocks to process.")
        var blocks: Int = 200

        @Option(name: .long, help: "Directory containing traces test vectors to run.")
        var tracesDir: String?

        func run() async throws {
            let env = ProcessInfo.processInfo.environment
            LoggingSystem.bootstrap { label in
                var handler = StreamLogHandler.standardOutput(label: label)
                handler.logLevel = parseLevel(env["LOG_LEVEL"] ?? "") ?? .info
                return handler
            }

            let fuzzer = try FuzzingClient(
                socketPath: socketPath,
                config: config.rawValue,
                seed: seed,
                blockCount: blocks,
                tracesDir: tracesDir
            )
            try await fuzzer.run()
        }
    }
}
