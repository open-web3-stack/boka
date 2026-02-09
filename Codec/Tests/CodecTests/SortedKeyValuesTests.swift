@testable import Codec
import Foundation
import Testing

struct SortedKeyValuesTests {
    @Test func encode() throws {
        let testCase: SortedKeyValues<UInt8, UInt8> = SortedKeyValues(alias: [1: 1, 2: 2, 3: 3])
        let encoded = try JamEncoder.encode(testCase)
        #expect(encoded == Data([3, 1, 1, 2, 2, 3, 3]))
        #expect(throws: DecodingError.self) {
            _ = try JamDecoder.decode(SortedKeyValues<UInt8, UInt8>.self, from: Data([3, 3, 3, 2, 2, 1, 1]))
        }
    }
}
