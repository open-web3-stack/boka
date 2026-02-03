@testable import Blockchain
import Testing
import Utils

struct ValidatorKeyTests {
    @Test
    func metadataString() throws {
        var key = ValidatorKey()
        #expect(key.metadataString == "")

        let addr = "127.0.0.1:5000"
        var addrData = Data(addr.utf8)
        addrData.append(contentsOf: Data(repeating: 0, count: 128 - addrData.count))
        key.metadata = try #require(Data128(addrData))
        #expect(key.metadataString == addr)

        let addr6 = "[2001:db8:85a3::8a2e:370:7334]:8080"
        addrData = Data(addr6.utf8)
        addrData.append(contentsOf: Data(repeating: 0, count: 128 - addrData.count))
        key.metadata = try #require(Data128(addrData))
        #expect(key.metadataString == addr6)
    }
}
