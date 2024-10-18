import Foundation
import Testing

@testable import Utils

struct RegexsTests {
    @Test func parseAddress() throws {
        // Correct IPv4 address
        #expect(try Regexs.parseAddress("127.0.0.1:9955") == ("127.0.0.1", 9955))

        // Correct IPv6 addresses
        #expect(try Regexs
            .parseAddress("[2001:0db8:85a3:0000:0000:8a2e:0370:7334]:8080") == ("2001:0db8:85a3:0000:0000:8a2e:0370:7334", 8080))
        #expect(try Regexs.parseAddress("[2001:db8:85a3::8a2e:370:7334]:8080") == ("2001:db8:85a3::8a2e:370:7334", 8080))
        #expect(try Regexs.parseAddress("[::1]:8080") == ("::1", 8080))

        // Exception case: Missing port
        #expect(throws: RegexsError.invalidFormat) { try Regexs.parseAddress("127.0.0.1") }
        #expect(throws: RegexsError.invalidFormat) { try Regexs.parseAddress("abcd:::") }
        // Exception case: Invalid port
        #expect(throws: RegexsError.invalidPort) { try Regexs.parseAddress("127.0.0.1:75535") }
        #expect(throws: RegexsError.invalidPort) { try Regexs.parseAddress("[2001:db8::1]:75535") }

        // Exception case: Invalid IPv4 format
        #expect(throws: RegexsError.invalidFormat) { try Regexs.parseAddress("256.256.256.256:8080") }

        // Exception case: Invalid IPv6 format
        #expect(throws: RegexsError.invalidFormat) { try Regexs.parseAddress("[2001:db8:::1]:8080") }
    }
}
