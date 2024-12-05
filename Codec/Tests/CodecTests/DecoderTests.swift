import Foundation
import Testing

@testable import Codec

struct DecoderTests {
    @Test func decodeData() throws {
        let encodedData = Data([3, 0, 1, 2])
        let decoded = try JamDecoder.decode(Data.self, from: encodedData)

        #expect(decoded == Data([0, 1, 2]))
    }

    @Test func decodeBool() throws {
        let encodedTrue = Data([1])
        let encodedFalse = Data([0])

        let decodedTrue = try JamDecoder.decode(Bool.self, from: encodedTrue)
        let decodedFalse = try JamDecoder.decode(Bool.self, from: encodedFalse)

        #expect(decodedTrue == true)
        #expect(decodedFalse == false)
    }

    @Test func decodeString() throws {
        let encoded = Data([5, 104, 101, 108, 108, 111])
        let decoded = try JamDecoder.decode(String.self, from: encoded)

        #expect(decoded == "hello")
    }

    @Test func decodeArray() throws {
        let encoded = Data([3, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0])
        let decoded = try JamDecoder.decode([Int].self, from: encoded)

        #expect(decoded == [1, 2, 3])
    }

    @Test func decodeInt() throws {
        let encoded = Data([1, 0, 0, 0, 0, 0, 0, 0])
        let decoded = try JamDecoder.decode(Int.self, from: encoded)

        #expect(decoded == 1)
    }

    @Test func decodeOptional() throws {
        let encodedSome = Data([1, 1, 0, 0, 0, 0, 0, 0, 0])
        let encodedNone = Data([0])

        let decodedSome = try JamDecoder.decode(Int?.self, from: encodedSome)
        let decodedNone = try JamDecoder.decode(Int?.self, from: encodedNone)

        #expect(decodedSome == .some(1))
        #expect(decodedNone == .none)
    }

    @Test func decodeFixedWidthInteger() throws {
        let encodedInt8 = Data([251])
        let encodedUInt64 = Data([21, 205, 91, 7, 0, 0, 0, 0])

        let decodedInt8 = try JamDecoder.decode(Int8.self, from: encodedInt8)
        let decodedUInt64 = try JamDecoder.decode(UInt64.self, from: encodedUInt64)

        #expect(decodedInt8 == -5)
        #expect(decodedUInt64 == 123_456_789)
    }

    @Test func decodeInvalidData() throws {
        let invalidEncodedData = Data([0, 0, 0, 123])
        #expect(throws: Error.self) {
            _ = try JamDecoder.decode(Int8.self, from: invalidEncodedData)
        }
    }

    @Test func decodeEmptyString() throws {
        let invalidEncodedData = Data()
        #expect(throws: Error.self) {
            _ = try JamDecoder.decode(String.self, from: invalidEncodedData)
        }
    }
}
