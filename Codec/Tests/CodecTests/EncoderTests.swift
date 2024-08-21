import Foundation
import Testing

@testable import Codec

// TODO: add more tests
struct EncoderTests {
    @Test func encodeData() throws {
        let data = Data([0, 1, 2])
        let encoded = try JamEncoder.encode(data)
        #expect(encoded == Data([3, 0, 1, 2]))
    }
}
