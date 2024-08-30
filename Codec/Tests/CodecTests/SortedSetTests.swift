import Foundation
import Testing

@testable import Codec

struct SortedSetTests {
    @Test func encode() throws {
        let testCase: SortedSet<UInt8> = SortedSet(alias: [1, 2, 3])
        let encoded = try JamEncoder.encode(testCase)
        #expect(encoded == Data([3, 1, 2, 3]))
    }

    @Test func decode() throws {
        let decoded = try JamDecoder.decode(SortedSet<UInt8>.self, from: Data([12, 1, 2, 3]))
        #expect(decoded.alias == [1, 2, 3])
    }

    @Test func invalidData() throws {
        #expect(throws: DecodingError.self) {
            try JamDecoder.decode(SortedSet<UInt>.self, from: Data([12, 1, 2, 2]))
        }

        #expect(throws: DecodingError.self) {
            try JamDecoder.decode(SortedSet<UInt>.self, from: Data([12, 3, 2, 1]))
        }
    }
}
