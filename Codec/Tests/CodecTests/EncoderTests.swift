import Foundation
import Testing

@testable import Codec

extension Data {
    public func toHexString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}

struct EncoderTests {
    @Test func encodeData() throws {
        let data = Data([0, 1, 2])
        let encoded = try JamEncoder.encode(data)
        #expect(encoded == Data([3, 0, 1, 2])) // Length prefix of 3 bytes
    }

    @Test func encodeBool() throws {
        let trueValue = true
        let falseValue = false

        let encodedTrue = try JamEncoder.encode(trueValue)
        let encodedFalse = try JamEncoder.encode(falseValue)

        #expect(encodedTrue == Data([1])) // True encoded as 1 byte
        #expect(encodedFalse == Data([0])) // False encoded as 1 byte
    }

    @Test func encodeString() throws {
        let stringValue = "hello"
        let encoded = try JamEncoder.encode(stringValue)

        #expect(encoded == Data([5, 104, 101, 108, 108, 111])) // Length prefix of 5 bytes and UTF-8 encoding of "hello"
    }

    @Test func encodeArray() throws {
        let arrayValue: [Int] = [1, 2, 3]
        let encoded = try JamEncoder.encode(arrayValue)
        #expect(encoded == Data([
            3,
            1,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            2,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            3,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
        ])) // Array with length prefix and encoded integers
    }

    @Test func encodeOptional() throws {
        let optionalValue: Int? = 1
        let encodedSome = try JamEncoder.encode(optionalValue)

        let encodedNone = try JamEncoder.encode(Int?.none)

        #expect(encodedSome == Data([1, 1, 0, 0, 0, 0, 0, 0, 0])) // Optional with value encoded
        #expect(encodedNone == Data([0])) // None encoded as 1 byte (0)
    }

    @Test func encodeInt() throws {
        let intValue = 123_456_789
        let encoded = try JamEncoder.encode(intValue)

        #expect(encoded == Data([21, 205, 91, 7, 0, 0, 0, 0])) // Integer with encoded size
    }

    @Test func encodeFixedWidthInteger() throws {
        let int8Value: Int8 = -5
        let uint64Value: UInt64 = 123_456_789

        let encodedInt8 = try JamEncoder.encode(int8Value)
        let encodedUInt64 = try JamEncoder.encode(uint64Value)

        #expect(encodedInt8 == Data([251])) // Int8 encoding (signed byte)
        #expect(encodedUInt64 == Data([21, 205, 91, 7, 0, 0, 0, 0])) // UInt64 encoding
    }
}
