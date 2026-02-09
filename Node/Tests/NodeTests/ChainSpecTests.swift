import Blockchain
import Foundation
@testable import Node
import Testing
import Utils

enum ResourceLoader {
    static func loadResource(named name: String) -> URL? {
        let bundle = Bundle.module
        return bundle.url(forResource: name, withExtension: nil, subdirectory: "chainfiles")
    }
}

struct ChainSpecTests {
    @Test func presetLoading() async throws {
        // Test loading different presets
        for preset in GenesisPreset.allCases {
            let genesis = Genesis.preset(preset)
            let chainspec = try await genesis.load()
            let backend = try StateBackend(InMemoryBackend(), config: chainspec.getConfig(), rootHash: Data32())
            let state = try chainspec.getState()
            try await backend.writeRaw(state.map { (key: $0.key, value: $0.value) })
            let block = try chainspec.getBlock()
            let config = try chainspec.getConfig()

            let recentHistory = try await backend.read(StateKeys.RecentHistoryKey())
            #expect(recentHistory?.items.last?.headerHash == block.hash)

            // Verify config matches preset
            #expect(config == preset.config)
        }
    }

    @Test func chainSpecFiles() async throws {
        // Test the JIP-4 compliant chainspec files
        let testCases = [
            ("spec-minimal.json", GenesisPreset.minimal),
            ("spec-dev.json", GenesisPreset.dev),
            ("spec-tiny.json", GenesisPreset.tiny),
        ]

        for (filename, expectedPreset) in testCases {
            let specPath = try #require(ResourceLoader.loadResource(named: filename)?.path())
            let genesis: Genesis = .file(path: specPath)
            let chainspec = try await genesis.load()

            #expect(chainspec.id == expectedPreset.rawValue)

            let config = try chainspec.getConfig()
            #expect(config == expectedPreset.config)

            let block = try chainspec.getBlock()
            #expect(block.extrinsic.tickets.tickets.isEmpty)
            #expect(block.extrinsic.disputes.verdicts.isEmpty)

            let state = try chainspec.getState()
            #expect(!state.isEmpty)
        }
    }

    @Test func encodeDecodeChainSpec() async throws {
        let genesis = Genesis.preset(.minimal)
        let chainspec = try await genesis.load()

        let data = try chainspec.encode()
        let decoded = try ChainSpec.decode(from: data)
        #expect(decoded == chainspec)
    }

    @Test func protocolParametersDecoding() async throws {
        let testCases = [
            ("spec-minimal.json", 3), // minimal has 3 validators
            ("spec-dev.json", 6), // dev has 6 validators
            ("spec-tiny.json", 6), // tiny has 6 validators
        ]

        for (filename, expectedValidators) in testCases {
            let specPath = try #require(ResourceLoader.loadResource(named: filename)?.path())
            let genesis: Genesis = .file(path: specPath)
            let chainspec = try await genesis.load()
            let config = try chainspec.getConfig()

            #expect(config.value.totalNumberOfValidators == expectedValidators)
        }
    }
}
