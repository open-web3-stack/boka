import Codec
import Foundation
import Testing

@testable import Utils

struct ReadIntValue: ReadInt {
    typealias TConfig = Int

    static func read(config: Int) -> Int {
        config
    }
}

struct ConfigSizeBitStringTests {
    @Test func notEnoughData() throws {
        let data = Data([0])
        let length = 9
        #expect(throws: ConfigSizeBitStringError.invalidData) {
            try ConfigSizeBitString<ReadIntValue>(config: length, data: data)
        }
    }

    @Test func tooMuchData() throws {
        let data = Data([0, 0])
        let length = 8
        #expect(throws: ConfigSizeBitStringError.invalidData) {
            try ConfigSizeBitString<ReadIntValue>(config: length, data: data)
        }
    }

    @Test func works() throws {
        var value = ConfigSizeBitString<ReadIntValue>(config: 7)
        #expect(value.binaryString == "0000000")

        value[0] = true
        #expect(Array(value) == [true, false, false, false, false, false, false])
        #expect(value.binaryString == "1000000")

        value[1] = true
        #expect(Array(value) == [true, true, false, false, false, false, false])
        #expect(value.binaryString == "1100000")

        value[6] = true
        #expect(Array(value) == [true, true, false, false, false, false, true])
        #expect(value.binaryString == "1100001")

        value[0] = false
        #expect(Array(value) == [false, true, false, false, false, false, true])
        #expect(value.binaryString == "0100001")
    }

    @Test func initWorks() throws {
        let data = Data([0b1011_0101])
        let length = 7
        let value = try ConfigSizeBitString<ReadIntValue>(config: length, data: data)
        #expect(Array(value) == [true, false, true, false, true, true, false])
        #expect(value.binaryString == "1010110")
    }

    @Test func largeInitWorks() throws {
        let data = Data([0b1011_0101, 0b1100_0101, 0b0010_0110])
        let length = 20
        var value = try ConfigSizeBitString<ReadIntValue>(config: length, data: data)
        #expect(Array(value) == [
            true, false, true, false,
            true, true, false, true,
            true, false, true, false,
            false, false, true, true,
            false, true, true, false,
        ])
        #expect(value.binaryString == "10101101101000110110")

        value[19] = true
        #expect(value[19] == true)
        #expect(value.binaryString == "10101101101000110111")

        #expect(throws: ConfigSizeBitStringError.invalidIndex) {
            _ = try value.at(20)
        }

        #expect(throws: ConfigSizeBitStringError.invalidIndex) {
            try value.set(20, to: true)
        }
    }

    @Test func codable() throws {
        let data = Data([0b1011_0101, 0b1100_0101, 0b0000_0110])
        let length = 20
        let value = try ConfigSizeBitString<ReadIntValue>(config: length, data: data)

        let encoded = try JamEncoder.encode(value)
        #expect(encoded == data)
        let decoded = try JamDecoder.decode(ConfigSizeBitString<ReadIntValue>.self, from: encoded, withConfig: length)
        #expect(decoded == value)
    }

    @Test func equatable() throws {
        let data = Data([0b1011_0101, 0b1100_0101, 0b0000_0110])
        let length = 20
        var value = try ConfigSizeBitString<ReadIntValue>(config: length, data: data)

        let length2 = 21
        let value2 = try ConfigSizeBitString<ReadIntValue>(config: length2, data: data)

        #expect(value == value)
        #expect(value != value2)

        var value3 = value
        value3[19] = true
        #expect(value3 != value)

        value[19] = true
        #expect(value == value3)
    }
}
