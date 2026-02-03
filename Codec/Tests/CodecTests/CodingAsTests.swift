@testable import Codec
import Foundation
import Testing

struct UInt8Alias: CodableAlias, Codable {
    typealias T = UInt8

    var extraByte: UInt8 = 0xAB
    var value: UInt8

    init(alias: UInt8) {
        value = alias
    }

    var alias: UInt8 {
        value
    }
}

struct TestCodable: Codable {
    @CodingAs<UInt8Alias> var value: UInt8
}

struct CodingAsTests {
    @Test func codingAs() throws {
        let testCase = TestCodable(value: 0x23)
        let encoded = try JamEncoder.encode(testCase)
        #expect(encoded == Data([0xAB, 0x23]))
        let decoded = try JamDecoder.decode(TestCodable.self, from: encoded, withConfig: testCase)
        #expect(decoded.value == 0x23)
    }
}
