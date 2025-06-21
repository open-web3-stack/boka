@testable import Codec
import Testing

struct CompactTests {
    @Test
    func testUInt8Compact() throws {
        let value: UInt8 = 255
        let compact = Compact(alias: value)

        let encoded = try JamEncoder.encode(compact)
        let decoded = try JamDecoder.decode(Compact<UInt8>.self, from: encoded)

        #expect(decoded.alias == value)
    }

    @Test
    func testUInt16Compact() throws {
        let value: UInt16 = 65535
        let compact = Compact(alias: value)

        let encoded = try JamEncoder.encode(compact)
        let decoded = try JamDecoder.decode(Compact<UInt16>.self, from: encoded)

        #expect(decoded.alias == value)
    }

    @Test
    func testUInt32Compact() throws {
        let value: UInt32 = 4_294_967_295
        let compact = Compact(alias: value)

        let encoded = try JamEncoder.encode(compact)
        let decoded = try JamDecoder.decode(Compact<UInt32>.self, from: encoded)

        #expect(decoded.alias == value)
    }

    @Test
    func testUInt64Compact() throws {
        let value: UInt64 = 1_234_567_890
        let compact = Compact(alias: value)

        let encoded = try JamEncoder.encode(compact)
        let decoded = try JamDecoder.decode(Compact<UInt64>.self, from: encoded)

        #expect(decoded.alias == value)
    }

    @Test
    func testUIntCompact() throws {
        let value: UInt = 987_654_321
        let compact = Compact(alias: value)

        let encoded = try JamEncoder.encode(compact)
        let decoded = try JamDecoder.decode(Compact<UInt>.self, from: encoded)

        #expect(decoded.alias == value)
    }

    @Test
    func testValueOutOfRangeError() throws {
        // Test decoding a value that's too large for UInt8
        let largeValue: UInt = 256
        let compact = Compact(alias: largeValue)

        let encoded = try JamEncoder.encode(compact)

        #expect(throws: DecodingError.self) {
            try JamDecoder.decode(Compact<UInt8>.self, from: encoded)
        }
    }

    @Test
    func testValueOutOfRangeErrorDetails() throws {
        // Test decoding a value that's too large for UInt8
        let largeValue: UInt = 256
        let compact = Compact(alias: largeValue)

        let encoded = try JamEncoder.encode(compact)

        do {
            _ = try JamDecoder.decode(Compact<UInt8>.self, from: encoded)
            #expect(Bool(false), "Expected decoding to throw an error")
        } catch let decodingError as DecodingError {
            if case let .dataCorrupted(context) = decodingError {
                #expect(context.debugDescription.contains("Value 256"))
                #expect(context.debugDescription.contains("out of range"))
                #expect(context.debugDescription.contains("UInt8"))
            } else {
                #expect(Bool(false), "Expected dataCorrupted decoding error")
            }
        }
    }

    @Test
    func testCompactEncodingErrorDirectly() throws {
        // Test CompactEncodingError types directly
        let outOfRangeError = CompactEncodingError.valueOutOfRange(value: "256", sourceType: "UInt", targetType: "UInt8")
        #expect(outOfRangeError.description.contains("Value 256"))
        #expect(outOfRangeError.description.contains("out of range"))

        let conversionError = CompactEncodingError.conversionFailed(
            value: "123",
            fromType: "String",
            toType: "UInt",
            reason: "invalid format"
        )
        #expect(conversionError.description.contains("Failed to convert"))
        #expect(conversionError.description.contains("invalid format"))
    }

    struct TestPrivilegedServices: Codable {
        var blessed: UInt32
        var assign: UInt32
        var designate: UInt32
        @CodingAs<SortedKeyValues<UInt32, Compact<UInt64>>> var basicGas: [UInt32: Compact<UInt64>]

        init(blessed: UInt32, assign: UInt32, designate: UInt32, basicGas: [UInt32: UInt64]) {
            self.blessed = blessed
            self.assign = assign
            self.designate = designate
            self.basicGas = basicGas.mapValues { Compact(alias: $0) }
        }
    }

    @Test
    func testCodingAsPropertyWrapper() throws {
        let original = TestPrivilegedServices(
            blessed: 1,
            assign: 2,
            designate: 3,
            basicGas: [1: 1000, 2: 2000, 3: 3000]
        )

        let encoded = try JamEncoder.encode(original)
        let decoded = try JamDecoder.decode(TestPrivilegedServices.self, from: encoded)

        #expect(decoded.blessed == original.blessed)
        #expect(decoded.assign == original.assign)
        #expect(decoded.designate == original.designate)
        #expect(decoded.basicGas.mapValues { $0.alias } == [1: 1000, 2: 2000, 3: 3000])
    }

    @Test
    func testZeroValues() throws {
        let zeroUInt8 = Compact(alias: UInt8(0))
        let zeroUInt32 = Compact(alias: UInt32(0))

        let encodedUInt8 = try JamEncoder.encode(zeroUInt8)
        let encodedUInt32 = try JamEncoder.encode(zeroUInt32)

        let decodedUInt8 = try JamDecoder.decode(Compact<UInt8>.self, from: encodedUInt8)
        let decodedUInt32 = try JamDecoder.decode(Compact<UInt32>.self, from: encodedUInt32)

        #expect(decodedUInt8.alias == 0)
        #expect(decodedUInt32.alias == 0)
    }

    @Test
    func testMaxValues() throws {
        let maxUInt8 = Compact(alias: UInt8.max)
        let maxUInt16 = Compact(alias: UInt16.max)

        let encodedUInt8 = try JamEncoder.encode(maxUInt8)
        let encodedUInt16 = try JamEncoder.encode(maxUInt16)

        let decodedUInt8 = try JamDecoder.decode(Compact<UInt8>.self, from: encodedUInt8)
        let decodedUInt16 = try JamDecoder.decode(Compact<UInt16>.self, from: encodedUInt16)

        #expect(decodedUInt8.alias == UInt8.max)
        #expect(decodedUInt16.alias == UInt16.max)
    }
}
