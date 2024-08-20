import Foundation
import Testing

@testable import Utils

@Suite struct BitStringTests {
    @Test func testBitString_01() {
        let binaryString = "01"
        let expectedLength = 2
        let expectedBytes = Data([0b0100_0000]) // "01" -> 0b01000000 in a single byte
        let bitString = Bitstring(binaryString)
        #expect(expectedBytes == bitString!.bytes)
        #expect(expectedLength == bitString!.length)
    }

    @Test func testBitString_100000001() {
        let binaryString = "100000001"
        let expectedLength = 9
        let expectedBytes = Data([0b1000_0000, 0b1000_0000]) // "100000001" -> 0b10000000 0b10000000 in two bytes
        let bitstring = Bitstring(binaryString)
        #expect(bitstring!.length == expectedLength)
        #expect(bitstring!.bytes == expectedBytes)
        #expect(bitstring!.binaryString == binaryString)
    }

    @Test func testInvalidBinaryString() {
        let invalidBinaryString = "02"
        let bitstring = Bitstring(invalidBinaryString)
        #expect(bitstring == nil)
        #expect(bitstring?.bitSquences == nil)
    }

    @Test func testinitBinaryStringWithLength() {
        let bitstring = Bitstring(length: 0)
        #expect(bitstring.length == 0)
    }
}
