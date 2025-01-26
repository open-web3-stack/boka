import ArgumentParser
import Codec
import Foundation
import Node
import Utils

struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate new chainspec file"
    )

    @Argument(help: "output file")
    var output: String

    @Option(name: .long, help: "A preset config or path to chain config file.")
    var chain: Genesis = .preset(.minimal)

    @Option(name: .long, help: "The chain name.")
    var name: String = "Devnet"

    @Option(name: .long, help: "The chain id.")
    var id: String = "dev"

    func run() async throws {
        let chainspec = try await chain.load()
        let data = try chainspec.encode()
        try data.write(to: URL(fileURLWithPath: output))

        print("Chainspec generated at \(output)")
    }
}
