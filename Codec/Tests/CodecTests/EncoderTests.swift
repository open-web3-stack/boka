import Foundation
import Testing

@testable import Codec

struct EncoderTests {
    struct TestStruct: Codable {
        let intValue: Int
        let optionalIntValue: Int?
        let optionalIntValue2: Int?
        let stringValue: String
        let optionalStringValue: String?
        let optionalStringValue2: String?
        let boolValue: Bool
        let optionalBoolValue: Bool?
        let optionalBoolValue2: Bool?
        let uintValue: UInt
        let optionalUintValue: UInt?
        let optionalUintValue2: UInt?
        let int8Value: Int8
        let optionalInt8Value: Int8?
        let optionalInt8Value2: Int8?
        let uint8Value: UInt8
        let optionalUint8Value: UInt8?
        let optionalUint8Value2: UInt8?
        let int16Value: Int16
        let optionalInt16Value: Int16?
        let optionalInt16Value2: Int16?
        let uint16Value: UInt16
        let optionalUint16Value: UInt16?
        let optionalUint16Value2: UInt16?
        let int32Value: Int32
        let optionalInt32Value: Int32?
        let optionalInt32Value2: Int32?
        let uint32Value: UInt32
        let optionalUint32Value: UInt32?
        let optionalUint32Value2: UInt32?
        let int64Value: Int64
        let optionalInt64Value: Int64?
        let optionalInt64Value2: Int64?
        let uint64Value: UInt64
        let optionalUint64Value: UInt64?
        let optionalUint64Value2: UInt64?
    }

    @Test
    func encodeDecodeFullStruct() throws {
        let testObject = TestStruct(
            intValue: 42,
            optionalIntValue: 42,
            optionalIntValue2: nil,
            stringValue: "hello",
            optionalStringValue: nil,
            optionalStringValue2: "world",
            boolValue: true,
            optionalBoolValue: nil,
            optionalBoolValue2: false,
            uintValue: 99,
            optionalUintValue: nil,
            optionalUintValue2: 100,
            int8Value: -12,
            optionalInt8Value: nil,
            optionalInt8Value2: 120,
            uint8Value: 255,
            optionalUint8Value: nil,
            optionalUint8Value2: 128,
            int16Value: -1234,
            optionalInt16Value: nil,
            optionalInt16Value2: 1234,
            uint16Value: 65535,
            optionalUint16Value: nil,
            optionalUint16Value2: 32767,
            int32Value: -123_456,
            optionalInt32Value: nil,
            optionalInt32Value2: 123_456,
            uint32Value: 4_294_967_295,
            optionalUint32Value: nil,
            optionalUint32Value2: 2_147_483_647,
            int64Value: -1_234_567_890_123,
            optionalInt64Value: nil,
            optionalInt64Value2: 1_234_567_890_123,
            uint64Value: 18_446_744_073_709_551_615,
            optionalUint64Value: nil,
            optionalUint64Value2: 9_223_372_036_854_775_807
        )

        let encoded = try JamEncoder.encode(testObject)
        #expect(encoded.count > 0)

        let decoded = try JamDecoder.decode(TestStruct.self, from: encoded)

        #expect(decoded.intValue == testObject.intValue)
        #expect(decoded.optionalIntValue == testObject.optionalIntValue)
        #expect(decoded.optionalIntValue2 == testObject.optionalIntValue2)
        #expect(decoded.stringValue == testObject.stringValue)
        #expect(decoded.optionalStringValue == testObject.optionalStringValue)
        #expect(decoded.optionalStringValue2 == testObject.optionalStringValue2)
        #expect(decoded.boolValue == testObject.boolValue)
        #expect(decoded.optionalBoolValue == testObject.optionalBoolValue)
        #expect(decoded.optionalBoolValue2 == testObject.optionalBoolValue2)
        #expect(decoded.uintValue == testObject.uintValue)
        #expect(decoded.optionalUintValue == testObject.optionalUintValue)
        #expect(decoded.optionalUintValue2 == testObject.optionalUintValue2)
        #expect(decoded.int8Value == testObject.int8Value)
        #expect(decoded.optionalInt8Value == testObject.optionalInt8Value)
        #expect(decoded.optionalInt8Value2 == testObject.optionalInt8Value2)
        #expect(decoded.uint8Value == testObject.uint8Value)
        #expect(decoded.optionalUint8Value == testObject.optionalUint8Value)
        #expect(decoded.optionalUint8Value2 == testObject.optionalUint8Value2)
        #expect(decoded.int16Value == testObject.int16Value)
        #expect(decoded.optionalInt16Value == testObject.optionalInt16Value)
        #expect(decoded.optionalInt16Value2 == testObject.optionalInt16Value2)
        #expect(decoded.uint16Value == testObject.uint16Value)
        #expect(decoded.optionalUint16Value == testObject.optionalUint16Value)
        #expect(decoded.optionalUint16Value2 == testObject.optionalUint16Value2)
        #expect(decoded.int32Value == testObject.int32Value)
        #expect(decoded.optionalInt32Value == testObject.optionalInt32Value)
        #expect(decoded.optionalInt32Value2 == testObject.optionalInt32Value2)
        #expect(decoded.uint32Value == testObject.uint32Value)
        #expect(decoded.optionalUint32Value == testObject.optionalUint32Value)
        #expect(decoded.optionalUint32Value2 == testObject.optionalUint32Value2)
        #expect(decoded.int64Value == testObject.int64Value)
        #expect(decoded.optionalInt64Value == testObject.optionalInt64Value)
        #expect(decoded.optionalInt64Value2 == testObject.optionalInt64Value2)
        #expect(decoded.uint64Value == testObject.uint64Value)
        #expect(decoded.optionalUint64Value == testObject.optionalUint64Value)
        #expect(decoded.optionalUint64Value2 == testObject.optionalUint64Value2)
    }

    @Test func encodeOpStruct() throws {
        struct DoubleStruct: Codable {
            let value: Double
        }
        struct OpDoubleStruct: Codable {
            let value: Double?
        }
        struct FloatStruct: Codable {
            let value: Float
        }
        struct OpFloatStruct: Codable {
            let value: Float?
        }
        #expect(throws: Error.self) {
            _ = try JamEncoder.encode(DoubleStruct(value: 0))
        }
        #expect(throws: Error.self) {
            _ = try JamEncoder.encode(OpDoubleStruct(value: 0))
        }
        #expect(throws: Error.self) {
            _ = try JamEncoder.encode(OpFloatStruct(value: 0))
        }
        #expect(throws: Error.self) {
            _ = try JamEncoder.encode(FloatStruct(value: 0))
        }

        struct DoubleTest: Encodable {
            let doubleValue: Double
            func encode(to encoder: Encoder) throws {
                var container = encoder.unkeyedContainer()
                try container.encode(doubleValue)
            }
        }
        #expect(throws: Error.self) {
            _ = try JamEncoder.encode(DoubleTest(doubleValue: 0))
        }

        struct FloatTest: Encodable {
            let floatValue: Float
            func encode(to encoder: Encoder) throws {
                var container = encoder.unkeyedContainer()
                try container.encode(floatValue)
            }
        }
        #expect(throws: Error.self) {
            _ = try JamEncoder.encode(FloatTest(floatValue: 0))
        }
    }

    struct UnkeyedTest: Codable {
        var boolValue: Bool
        let stringValue: String
        let intValue: Int
        let int8Value: Int8
        let int16Value: Int16
        let int32Value: Int32
        let int64Value: Int64
        let uintValue: UInt
        let uint8Value: UInt8
        let uint16Value: UInt16
        let uint32Value: UInt32
        let uint64Value: UInt64
        let dataValue: Data
        let nestedValues: [UnkeyedTest]

        func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(boolValue)
            try container.encode(stringValue)
            try container.encode(intValue)
            try container.encode(int8Value)
            try container.encode(int16Value)
            try container.encode(int32Value)
            try container.encode(int64Value)
            try container.encode(uintValue)
            try container.encode(uint8Value)
            try container.encode(uint16Value)
            try container.encode(uint32Value)
            try container.encode(uint64Value)
            try container.encode(dataValue)
            try container.encode(nestedValues)
        }

        init(boolValue: Bool = false,
             stringValue: String = "",
             intValue: Int = 0,
             int8Value: Int8 = 0,
             int16Value: Int16 = 0,
             int32Value: Int32 = 0,
             int64Value: Int64 = 0,
             uintValue: UInt = 0,
             uint8Value: UInt8 = 0,
             uint16Value: UInt16 = 0,
             uint32Value: UInt32 = 0,
             uint64Value: UInt64 = 0,
             dataValue: Data = Data(),
             nestedValues: [UnkeyedTest] = [])
        {
            self.boolValue = boolValue
            self.stringValue = stringValue
            self.intValue = intValue
            self.int8Value = int8Value
            self.int16Value = int16Value
            self.int32Value = int32Value
            self.int64Value = int64Value
            self.uintValue = uintValue
            self.uint8Value = uint8Value
            self.uint16Value = uint16Value
            self.uint32Value = uint32Value
            self.uint64Value = uint64Value
            self.dataValue = dataValue
            self.nestedValues = nestedValues
        }

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            boolValue = try container.decode(Bool.self)
            stringValue = try container.decode(String.self)
            intValue = try container.decode(Int.self)
            int8Value = try container.decode(Int8.self)
            int16Value = try container.decode(Int16.self)
            int32Value = try container.decode(Int32.self)
            int64Value = try container.decode(Int64.self)
            uintValue = try container.decode(UInt.self)
            uint8Value = try container.decode(UInt8.self)
            uint16Value = try container.decode(UInt16.self)
            uint32Value = try container.decode(UInt32.self)
            uint64Value = try container.decode(UInt64.self)
            dataValue = try container.decode(Data.self)
            nestedValues = try container.decode([UnkeyedTest].self)
        }
    }

    @Test func testUnkeyedContainer() throws {
        let testData = UnkeyedTest(
            boolValue: true,
            stringValue: "Hello",
            intValue: 42,
            int8Value: Int8(8),
            int16Value: Int16(16),
            int32Value: Int32(32),
            int64Value: Int64(64),
            uintValue: UInt(128),
            uint8Value: UInt8(8),
            uint16Value: UInt16(16),
            uint32Value: UInt32(32),
            uint64Value: UInt64(64),
            dataValue: Data([0x01, 0x02, 0x03]),
            nestedValues: [
                UnkeyedTest(
                    boolValue: false,
                    stringValue: "Nested",
                    intValue: 99,
                    int8Value: 1,
                    int16Value: 2,
                    int32Value: 3,
                    int64Value: 4,
                    uintValue: 5,
                    uint8Value: 6,
                    uint16Value: 7,
                    uint32Value: 8,
                    uint64Value: 9,
                    dataValue: Data([0x01]),
                    nestedValues: []
                ),
            ]
        )

        let encoded = try JamEncoder.encode(testData)
        #expect(encoded.count > 0)
        let decoded = try JamDecoder.decode(UnkeyedTest.self, from: encoded, withConfig: testData)
        #expect(testData.intValue == decoded.intValue)
        #expect(testData.dataValue == decoded.dataValue)
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
