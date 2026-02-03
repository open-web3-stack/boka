import ArgumentParser
import Codec
import Foundation
import Node
import Utils

extension GenesisPreset: @retroactive ExpressibleByArgument {}

struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a JIP 4 chainspec file",
    )

    @Argument(help: "output file")
    var output: String

    @Option(name: .long, help: "A JAM preset config.")
    var config: GenesisPreset = .minimal

    @Option(name: .long, help: "Path to existing chainspec file to use. This has priority over the preset config.")
    var chainspec: String?

    @Option(name: .long, help: "The chain id.")
    var id: String?

    func run() async throws {
        let genesis: Genesis = if let chainspecPath = chainspec {
            .file(path: chainspecPath)
        } else {
            .preset(config)
        }

        var chainSpec = try await genesis.load()

        if let customId = id {
            chainSpec.id = customId
        }

        let data = try chainSpec.encode()
        try data.write(to: URL(fileURLWithPath: output))

        print("Chainspec generated at \(output)")
    }
}
