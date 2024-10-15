import Blockchain
import ConsoleKit
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

final class BokaTests {
    var console: Terminal
    var boka: Boka
    init() {
        console = Terminal()
        boka = Boka()
    }

    @Test func missCommand() async throws {
        let sepc = ResourceLoader.loadResource(named: "devnet_allconfig_spec.json")!.path()
        print("path = \(sepc)")
        let input = CommandInput(arguments: ["Boka", "-m", sepc])
        await #expect(throws: Error.self) {
            try await console.run(boka, input: input)
        }
    }

    @Test func commandWithAllConfig() async throws {
        let sepc = ResourceLoader.loadResource(named: "devnet_allconfig_spec.json")!.path()
        let genesis: Genesis = .file(path: sepc)
        let (_, protocolConfig) = try await genesis.load()
        #expect(protocolConfig.value.maxWorkItems == 2)
        #expect(protocolConfig.value.serviceMinBalance == 100)
    }

    @Test func commandWithSomeConfig() async throws {
        let sepc = ResourceLoader.loadResource(named: "mainnet_someconfig_spec.json")!.path()
        let genesis: Genesis = .file(path: sepc)
        let config = ProtocolConfigRef.mainnet.value
        let (_, protocolConfig) = try await genesis.load()
        #expect(protocolConfig.value.auditTranchePeriod == 100)
        #expect(protocolConfig.value.pvmProgramInitSegmentSize == config.pvmProgramInitSegmentSize)
    }

    @Test func commandWithNoConfig() async throws {
        let sepc = ResourceLoader.loadResource(named: "devnet_noconfig_spec.json")!.path()
        let genesis: Genesis = .file(path: sepc)
        let config = ProtocolConfigRef.dev.value
        let (_, protocolConfig) = try await genesis.load()
        #expect(protocolConfig.value.maxWorkItems == config.maxWorkItems)
        #expect(protocolConfig.value.serviceMinBalance == config.serviceMinBalance)
    }

    @Test func commandWithWrongFilePath() async throws {
        let sepc = "/path/to/wrong/file.json"
        let input = CommandInput(arguments: ["Boka", "--config-file", sepc])
        await #expect(throws: Error.self) {
            try await console.run(boka, input: input)
        }
    }
}
