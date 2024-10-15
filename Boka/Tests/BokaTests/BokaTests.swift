import ConsoleKit
import Foundation
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
        print("path = \(sepc)")
        let input = CommandInput(arguments: ["Boka", "-f", sepc])
        try await console.run(boka, input: input)
    }

    @Test func commandWithWrongFilePath() async throws {
        let sepc = "/path/to/wrong/file.json"
        let input = CommandInput(arguments: ["Boka", "--config-file", sepc])
        await #expect(throws: Error.self) {
            try await console.run(boka, input: input)
        }
    }
}
