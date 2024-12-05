import Foundation
import Testing

@testable import Codec

extension Double: EncodedSize, @retroactive Error {
    public var encodedSize: Int {
        MemoryLayout<Double>.size
    }

    public static var encodeedSizeHint: Int? {
        MemoryLayout<Double>.size
    }
}

extension Float: EncodedSize, @retroactive Error {
    public var encodedSize: Int {
        MemoryLayout<Float>.size
    }

    public static var encodeedSizeHint: Int? {
        MemoryLayout<Float>.size
    }
}

struct EncoderTests {
    struct TestStruct: Codable {
        let intValue: Int
        let optionalIntValue: Int?
        let stringValue: String
        let optionalStringValue: String?
        let boolValue: Bool
        let optionalBoolValue: Bool?
        let uintValue: UInt
        let optionalUintValue: UInt?
        let int8Value: Int8
        let optionalInt8Value: Int8?
        let uint8Value: UInt8
        let optionalUint8Value: UInt8?
        let int16Value: Int16
        let optionalInt16Value: Int16?
        let uint16Value: UInt16
        let optionalUint16Value: UInt16?
        let int32Value: Int32
        let optionalInt32Value: Int32?
        let uint32Value: UInt32
        let optionalUint32Value: UInt32?
        let int64Value: Int64
        let optionalInt64Value: Int64?
        let uint64Value: UInt64
        let optionalUint64Value: UInt64?
    }

    @Test
    func encodeDecodeFullStruct() throws {
        let testObject = TestStruct(
            intValue: 42,
            optionalIntValue: 42,
            stringValue: "hello",
            optionalStringValue: nil,
            boolValue: true,
            optionalBoolValue: nil,
            uintValue: 99,
            optionalUintValue: nil,
            int8Value: -12,
            optionalInt8Value: nil,
            uint8Value: 255,
            optionalUint8Value: nil,
            int16Value: -1234,
            optionalInt16Value: nil,
            uint16Value: 65535,
            optionalUint16Value: nil,
            int32Value: -123_456,
            optionalInt32Value: nil,
            uint32Value: 4_294_967_295,
            optionalUint32Value: nil,
            int64Value: -1_234_567_890_123,
            optionalInt64Value: nil,
            uint64Value: 18_446_744_073_709_551_615,
            optionalUint64Value: nil
        )

        let encoded = try JamEncoder.encode(testObject)

        #expect(encoded.count > 0)

        let decoded = try JamDecoder.decode(TestStruct.self, from: encoded)

        #expect(decoded.intValue == testObject.intValue)
        #expect(decoded.optionalIntValue == testObject.optionalIntValue)
        #expect(decoded.stringValue == testObject.stringValue)
        #expect(decoded.optionalStringValue == testObject.optionalStringValue)
        #expect(decoded.boolValue == testObject.boolValue)
        #expect(decoded.optionalBoolValue == testObject.optionalBoolValue)
        #expect(decoded.uintValue == testObject.uintValue)
        #expect(decoded.optionalUintValue == testObject.optionalUintValue)
        #expect(decoded.int8Value == testObject.int8Value)
        #expect(decoded.optionalInt8Value == testObject.optionalInt8Value)
        #expect(decoded.uint8Value == testObject.uint8Value)
        #expect(decoded.optionalUint8Value == testObject.optionalUint8Value)
        #expect(decoded.int16Value == testObject.int16Value)
        #expect(decoded.optionalInt16Value == testObject.optionalInt16Value)
        #expect(decoded.uint16Value == testObject.uint16Value)
        #expect(decoded.optionalUint16Value == testObject.optionalUint16Value)
        #expect(decoded.int32Value == testObject.int32Value)
        #expect(decoded.optionalInt32Value == testObject.optionalInt32Value)
        #expect(decoded.uint32Value == testObject.uint32Value)
        #expect(decoded.optionalUint32Value == testObject.optionalUint32Value)
        #expect(decoded.int64Value == testObject.int64Value)
        #expect(decoded.optionalInt64Value == testObject.optionalInt64Value)
        #expect(decoded.uint64Value == testObject.uint64Value)
        #expect(decoded.optionalUint64Value == testObject.optionalUint64Value)
    }

    @Test func encodeDouble() throws {
        #expect(throws: Error.self) {
            _ = try JamEncoder.encode(Double(1.0))
        }
    }

    @Test func encodeFloat() throws {
        #expect(throws: Error.self) {
            _ = try JamEncoder.encode(Float(1.0))
        }
    }

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
