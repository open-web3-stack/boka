import Blockchain
import Foundation
import Node
import Testing

@testable import Boka

struct BokaTests {
    @Test func commandWithInvalidPaths() async throws {
        let invalidChainPath = "/path/to/wrong/file.json"
        let invalidKeystorePath = "/path/to/invalid/keystore"

        var boka = try Boka.parseAsRoot([
            "--chain", invalidChainPath,
            "--keystore-path", invalidKeystorePath,
        ]) as! Boka

        await #expect(throws: Error.self) {
            try await boka.run()
        }
    }
}
