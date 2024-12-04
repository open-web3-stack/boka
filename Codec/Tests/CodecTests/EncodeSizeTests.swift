import Foundation
import Testing

@testable import Codec

extension Int: EncodedSize, @retroactive Error {
    public var encodedSize: Int {
        MemoryLayout<Int>.size
    }

    public static var encodeedSizeHint: Int? {
        MemoryLayout<Int>.size
    }
}

struct EncodeSizeTests {
    @Test
    func encodeFixedWidthInteger() throws {
        #expect(Int(42).encodedSize == MemoryLayout<Int>.size)
        #expect(Int8(-5).encodedSize == MemoryLayout<Int8>.size)
        #expect(UInt32(123_456).encodedSize == MemoryLayout<UInt32>.size)
        #expect(Int.encodeedSizeHint == MemoryLayout<Int>.size)
        #expect(Int8.encodeedSizeHint == MemoryLayout<Int8>.size)
        #expect(UInt32.encodeedSizeHint == MemoryLayout<UInt32>.size)
    }

    @Test
    func encodeBool() throws {
        #expect(true.encodedSize == 1)
        #expect(false.encodedSize == 1)
        #expect(Bool.encodeedSizeHint == 1)
    }

    @Test
    func encodeStringAndData() throws {
        #expect("test".encodedSize == 4)
        #expect("".encodedSize == 0)
        #expect(Data([0x01, 0x02, 0x03]).encodedSize == 4)
        #expect(Data().encodedSize == 1)
        #expect(String.encodeedSizeHint == nil)
        #expect(Data.encodeedSizeHint == nil)
    }

    @Test
    func encodeArrayAndSet() throws {
        let intArray = [1, 2, 3]
        let emptyArray: [Int] = []
        let intSet: Set<Int> = [4, 5, 6]
        let emptySet: Set<Int> = []

        #expect(intArray.encodedSize == UInt32(3).variableEncodingLength() + 3 * MemoryLayout<Int>.size)
        #expect(emptyArray.encodedSize == UInt32(0).variableEncodingLength())
        #expect(intSet.encodedSize >= UInt32(3).variableEncodingLength())
        #expect(emptySet.encodedSize == UInt32(0).variableEncodingLength())
        #expect([Int].encodeedSizeHint == nil)
        #expect(Set<Int>.encodeedSizeHint == nil)
    }

    @Test
    func encodeDictionary() throws {
        let dict: [Int: String] = [1: "one", 2: "two"]
        let emptyDict: [Int: String] = [:]

        let expectedSize = UInt32(2).variableEncodingLength() +
            1.encodedSize + "one".encodedSize +
            1.encodedSize + "two".encodedSize

        #expect(dict.encodedSize == expectedSize)
        #expect(emptyDict.encodedSize == UInt32(0).variableEncodingLength())
        #expect([Int: String].encodeedSizeHint == nil)
    }

    @Test
    func encodeOptional() throws {
        let someValue: Int? = 42
        let noneValue: Int? = nil

        #expect(someValue.encodedSize == 1 + MemoryLayout<Int>.size)
        #expect(noneValue.encodedSize == 1)
        #expect(Int?.encodeedSizeHint == nil)
    }

    @Test
    func encodeResult() throws {
        let successResult: Result<String, Int> = .success("OK")
        let failureResult: Result<String, Int> = .failure(404)

        #expect(successResult.encodedSize == 1 + "OK".encodedSize)
        #expect(failureResult.encodedSize == 1 + MemoryLayout<Int>.size)
        #expect(Result<String, Int>.encodeedSizeHint == nil)
    }
}
