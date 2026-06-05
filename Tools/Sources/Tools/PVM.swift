import ArgumentParser
import Blockchain
import Codec
import Foundation
import PolkaVM
import TracingUtils
import Utils

private let logger = Logger(label: "PVM")

struct PVM: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "PVM tools",
        subcommands: [
            Invoke.self,
        ],
    )

    struct Invoke: AsyncParsableCommand {
        @Argument(help: "Program blob path")
        var programPath: String

        @Option(help: "Program argument data path")
        var argumentPath: String?

        @Option(help: "Program argument data in hex")
        var argumentHex: String?

        @Option(help: "PC")
        var pc: UInt32 = 0

        @Option(help: "Gas")
        var gas: UInt64 = 100_000_000

        func run() async throws {
            let blob: Data = try Data(contentsOf: URL(fileURLWithPath: programPath))
            let argumentData = if let argumentPath {
                try Data(contentsOf: URL(fileURLWithPath: argumentPath))
            } else if let argumentHex {
                Data(fromHexString: argumentHex).expect("invalid argument hex")
            } else {
                Data()
            }

            logger.info("ArgumentData: \(argumentData.toHexString())")

            // setupTestLogger()

            let config = DefaultPvmConfig()
            let gasValue = Gas(gas)

            let (exitReason, gasUsed, output) = await invokePVM(
                config: config,
                blob: blob,
                pc: pc,
                gas: gasValue,
                argumentData: argumentData,
                ctx: nil,
            )

            logger.info("Gas used: \(gasUsed)")
            if let output {
                logger.info("Output: \(output.toHexString())")
            }
            logger.info("ExitReason: \(exitReason)")
        }
    }
}
