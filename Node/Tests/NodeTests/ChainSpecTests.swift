import Blockchain
import Foundation
import Testing

@testable import Node

enum ResourceLoader {
    static func loadResource(named name: String) -> URL? {
        let bundle = Bundle.module
        return bundle.url(forResource: name, withExtension: nil, subdirectory: "chainfiles")
    }
}

struct ChainSpecTests {
    @Test func testPresetLoading() async throws {
        // Test loading different presets
        for preset in GenesisPreset.allCases {
            let genesis = Genesis.preset(preset)
            let chainspec = try await genesis.load()
            let backend = try InMemoryBackend(config: chainspec.getConfig(), store: chainspec.getState())
            let block = try chainspec.getBlock()
            let config = try chainspec.getConfig()

            let recentHistory = try await backend.read(StateKeys.RecentHistoryKey())
            #expect(recentHistory.items.last?.headerHash == block.hash)

            // Verify config matches preset
            #expect(config == preset.config)
        }
    }

    @Test func encodeDecodeChainSpec() async throws {
        let genesis = Genesis.preset(.minimal)
        let chainspec = try await genesis.load()

        let data = try chainspec.encode()
        let decoded = try ChainSpec.decode(from: data)
        #expect(decoded == chainspec)
    }

    @Test func commandWithAllConfig() async throws {
        let sepc = ResourceLoader.loadResource(named: "devnet_allconfig_spec.json")!.path()
        let genesis: Genesis = .file(path: sepc)
        let chainspec = try await genesis.load()
        let protocolConfig = try chainspec.getConfig()
        #expect(protocolConfig.value.maxWorkItems == 2)
        #expect(protocolConfig.value.serviceMinBalance == 100)
    }

    @Test func commandWithSomeConfig() async throws {
        let sepc = ResourceLoader.loadResource(named: "mainnet_someconfig_spec.json")!.path()
        let genesis: Genesis = .file(path: sepc)
        let config = ProtocolConfigRef.mainnet.value
        let chainspec = try await genesis.load()
        let protocolConfig = try chainspec.getConfig()
        #expect(protocolConfig.value.auditTranchePeriod == 100)
        #expect(protocolConfig.value.slotPeriodSeconds == config.slotPeriodSeconds)
    }

    @Test func commandWithNoConfig() async throws {
        let sepc = ResourceLoader.loadResource(named: "devnet_noconfig_spec.json")!.path()
        let genesis: Genesis = .file(path: sepc)
        let config = ProtocolConfigRef.dev.value
        let chainspec = try await genesis.load()
        let protocolConfig = try chainspec.getConfig()
        #expect(protocolConfig.value.maxWorkItems == config.maxWorkItems)
        #expect(protocolConfig.value.serviceMinBalance == config.serviceMinBalance)
    }
}
