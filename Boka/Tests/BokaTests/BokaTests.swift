import Blockchain
@testable import Boka
import Foundation
import Node
import Testing

struct BokaTests {
    @Test func commandWithInvalidPaths() async throws {
        let invalidChainPath = "/path/to/wrong/file.json"

        var boka = try #require(Boka.parseAsRoot([
            "--chain", invalidChainPath,
        ]) as? Boka)

        await #expect(throws: Error.self) {
            try await boka.run()
        }
    }
}
