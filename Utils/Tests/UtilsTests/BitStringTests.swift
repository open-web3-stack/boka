import Foundation
import Testing

@testable import Utils

@Suite struct BitStringTests {
    @Test func testBitString_01() throws {
        let binaryString = "01"
        let expectedLength = 2
        let expectedBytes = Data([0b01000000]) // "01" -> 0b01000000 in a single byte
        let bitString = Bitstring(binaryString)
        #expect(expectedBytes == bitString!.bytes)
        #expect(expectedLength == bitString!.length)

    }
    @Test func testBitString_100000001() throws {
        let binaryString: String = "100000001"
        let expectedLength = 9
        let expectedBytes = Data([0b10000000, 0b10000000]) // "100000001" -> 0b10000000 0b10000000 in two bytes
        if let bitstring = Bitstring(binaryString) {
            #expect(bitstring.length == expectedLength)
            #expect(bitstring.bytes == expectedBytes)
        }
    }
}
