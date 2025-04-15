import ArgumentParser
import RPC
import TracingUtils
import Utils

@main
struct Boka: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Boka Tools",
        version: "0.0.1",
        subcommands: [
            OpenRPC.self,
            PVM.self,
        ]
    )

    mutating func run() async throws {}
}
