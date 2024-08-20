import Foundation
import Testing

@testable import Codec

struct EncoderTests {
    @Test func encodeData() throws {
        let data = Data([0, 1, 2])
        let encoder = JamEncoder()
        let encoded = try encoder.encode(data)
        #expect(encoded == Data([3, 0, 1, 2]))
    }
}
