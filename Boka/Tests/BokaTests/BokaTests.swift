import Blockchain
import Foundation
import Node
import Testing

@testable import Boka

enum ResourceLoader {
    static func loadResource(named name: String) -> URL? {
        let bundle = Bundle.module
        return bundle.url(forResource: name, withExtension: nil, subdirectory: "chainfiles")
    }
}

struct BokaTests {
    @Test func commandWithWrongFilePath() async throws {
        let sepc = "/path/to/wrong/file.json"
        var boka = try Boka.parseAsRoot(["--chain", sepc]) as! Boka
        await #expect(throws: GenesisError.self) {
            try await boka.run()
        }
    }

    @Test func commandWithAllConfig() async throws {
        let sepc = ResourceLoader.loadResource(named: "devnet_allconfig_spec.json")!.path()
        let genesis: Genesis = .file(path: sepc)
        let (_, _, protocolConfig) = try await genesis.load()
        #expect(protocolConfig.value.maxWorkItems == 2)
        #expect(protocolConfig.value.serviceMinBalance == 100)
    }

    @Test func commandWithSomeConfig() async throws {
        let sepc = ResourceLoader.loadResource(named: "mainnet_someconfig_spec.json")!.path()
        let genesis: Genesis = .file(path: sepc)
        let config = ProtocolConfigRef.mainnet.value
        let (_, _, protocolConfig) = try await genesis.load()
        #expect(protocolConfig.value.auditTranchePeriod == 100)
        #expect(protocolConfig.value.pvmProgramInitSegmentSize == config.pvmProgramInitSegmentSize)
    }

    @Test func commandWithNoConfig() async throws {
        let sepc = ResourceLoader.loadResource(named: "devnet_noconfig_spec.json")!.path()
        let genesis: Genesis = .file(path: sepc)
        let config = ProtocolConfigRef.dev.value
        let (_, _, protocolConfig) = try await genesis.load()
        #expect(protocolConfig.value.maxWorkItems == config.maxWorkItems)
        #expect(protocolConfig.value.serviceMinBalance == config.serviceMinBalance)
    }
}
