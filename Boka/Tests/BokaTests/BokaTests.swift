import Blockchain
import Foundation
import Node
import Testing

@testable import Boka

struct BokaTests {
    @Test func commandWithWrongFilePath() async throws {
        let sepc = "/path/to/wrong/file.json"
        var boka = try Boka.parseAsRoot(["--chain", sepc]) as! Boka
        await #expect(throws: GenesisError.self) {
            try await boka.run()
        }
    }
}
