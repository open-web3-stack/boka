import Foundation
import Testing

@testable import Networking

struct AlpnTests {
    @Test func invalidAlpn() throws {
        #expect(throws: QuicError.invalidAlpn) {
            try Alpn(genesisHeader: "jam")
        }
    }

    @Test func validAlpn() throws {
        var alpn = try Alpn(version: "1.2", genesisHeader: "jamabcdefg")
        #expect(alpn.alpnString == "jamnp-s/1.2/jama")
    }
}
