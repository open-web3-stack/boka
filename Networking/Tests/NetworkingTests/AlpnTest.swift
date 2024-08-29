import Foundation
import Testing

@testable import Networking

struct AlpnTests {
    @Test func invalidAlpn() throws {
        #expect(throws: QuicError.invalidAlpn) {
            try Alpn(version: 0, genesisHeader: Data("jam".utf8))
        }
    }
}
