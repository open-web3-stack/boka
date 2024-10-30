import ArgumentParser
import Codec
import Foundation
import Node
import Utils

enum OutputFormat: String, ExpressibleByArgument {
    case json
    case binary
}

struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate new chainspec file"
    )

    @Argument(help: "output file")
    var output: String

    @Option(name: .long, help: "A preset config or path to chain config file.")
    var chain: Genesis = .preset(.minimal)

    @Option(name: .long, help: "The output format. json or binary.")
    var format: OutputFormat = .json

    @Option(name: .long, help: "The chain name.")
    var name: String = "Devnet"

    @Option(name: .long, help: "The chain id.")
    var id: String = "dev"

    func run() async throws {
        let (state, block, config) = try await chain.load()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.dataEncodingStrategy = .hex

        let genesis: any Encodable = switch format {
        case .json:
            GenesisData(
                name: name,
                id: id,
                bootnodes: [],
                preset: nil,
                config: config.value,
                block: block.value,
                state: state.value
            )
        case .binary:
            try GenesisDataBinary(
                name: name,
                id: id,
                bootnodes: [],
                preset: nil,
                config: config.value,
                block: JamEncoder.encode(block),
                state: JamEncoder.encode(state)
            )
        }

        let data = try encoder.encode(genesis)
        try data.write(to: URL(fileURLWithPath: output))

        print("Chainspec generated at \(output)")
    }
}
