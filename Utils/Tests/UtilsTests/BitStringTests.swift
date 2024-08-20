import Foundation
import Testing

@testable import Utils

@Suite struct BitStringTests {
    @Test func testBitString_01() throws {
        let binaryString = "01"
        let expectedLength = 2
        let expectedBytes = Data([0b01000000]) // "01" -> 0b01000000 in a single byte
        let bitString = try Bitstring(binaryString)
        #expect(expectedBytes == bitString.bytes)
        #expect(expectedLength == bitString.length)
    }
    @Test func testBitString_100000001() throws {
        let binaryString: String = "100000001"
        let expectedLength = 9
        let expectedBytes = Data([0b10000000, 0b10000000]) // "100000001" -> 0b10000000 0b10000000 in two bytes
        let bitstring = try Bitstring(binaryString) 
        #expect(bitstring.length == expectedLength)
        #expect(bitstring.bytes == expectedBytes)
        #expect(bitstring.binaryString == binaryString)
}
    @Test func testInvalidBinaryString() throws {
        let invalidBinaryString = "02"
        do {
            _ = try Bitstring(invalidBinaryString)
        } catch {
            print(error)
            #expect(true)
        }
    }
    @Test func testinitBinaryStringWithLength() throws {
        let bitstring = Bitstring(length: 341)
        print(bitstring.bitString)
        print(bitstring.binaryString)
    }
    
}
