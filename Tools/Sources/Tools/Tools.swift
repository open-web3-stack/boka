import ArgumentParser
import RPC
import TracingUtils
import Utils

@main
struct Tools: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Boka Tools",
        version: "0.0.1",
        subcommands: [
            OpenRPC.self,
            PVM.self,
            POC.self,
        ]
    )

    mutating func run() async throws {}
}
