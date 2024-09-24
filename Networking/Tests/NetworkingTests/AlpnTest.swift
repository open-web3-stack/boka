import Foundation
import Testing

@testable import Networking

struct AlpnTests {
    @Test func invalidAlpn() throws {
        #expect(throws: QuicError.invalidAlpn) {
            try Alpn(version: 0, genesisHeader: Data("jam".utf8))
        }
    }

    @Test func validAlpn() throws {
        let alpn = try Alpn(version: 0, genesisHeader: Data("jamabcdefg".utf8))
        #expect(alpn.alpnString == "jamnp-s/0/jama")
    }
}
