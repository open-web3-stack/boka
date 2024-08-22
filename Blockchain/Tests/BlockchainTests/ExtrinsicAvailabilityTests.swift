import Blockchain
import Foundation
import Testing
import Utils

struct ExtrinsicAvailabilityTests {
    @Test func errorAssuranceTest() throws {
        let data = Data([0b0101_0101])
        let config = ProtocolConfigRef.mainnet
        do {
            let res = try FixSizeBitstring<ProtocolConfig.TotalNumberOfCores>(
                config: config, data: data
            )
            print(res.binaryString)
        } catch {
            #expect(error != nil)
        }
    }

    @Test func AssuranceTest() throws {
        let count = (341 + 7) / 8 // bits / 8 = bytes
        let binaryString = (0 ..< count).map { _ in "01010101" }.joined()
        let data = Data((0 ..< count).map { _ in [0b0101_0101] }.joined())
        let config = ProtocolConfigRef.mainnet
        let res = try FixSizeBitstring<ProtocolConfig.TotalNumberOfCores>(
            config: config, data: data
        )
        #expect(res.binaryString == String(binaryString.prefix(341)))
    }
}
