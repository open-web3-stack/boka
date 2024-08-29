import Foundation
@testable import Networking
import Testing

@Test func invalidGenesis() async throws {
    #expect(throws: AlpnError.invalidGenesis) {
        try Alpn(version: 0, genesisHeader: Data("jam".utf8))
    }
}
