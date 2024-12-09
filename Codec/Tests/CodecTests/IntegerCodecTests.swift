import Foundation
import Testing

@testable import Codec

@Suite struct IntegerCodecTests {
    static func fixedWidthTestCasesSimple() -> [(UInt8, EncodeMethod, [UInt8])] {
        [
            (42, .fixedWidth(0), []),
            (42, .fixedWidth(1), [42]),
            (42, .fixedWidth(2), [42, 0]),
            (42, .fixedWidth(3), [42, 0, 0]),
        ]
    }

    @Test(arguments: fixedWidthTestCasesSimple())
    func fixedWidthTestCasesSimple(testCase: (UInt8, EncodeMethod, [UInt8])) {
        let (value, method, expected) = testCase
        let array = Array(value.encode(method: method))
        #expect(array == expected)
    }

    static func fixedWidthTestCasesComplex() -> [(UInt64, EncodeMethod, [UInt8])] {
        [
            (0, .fixedWidth(0), []),
            (1, .fixedWidth(1), [1]),
            (255, .fixedWidth(1), [255]),
            (256, .fixedWidth(2), [0, 1]),
            (257, .fixedWidth(3), [1, 1, 0]),
            (UInt64(1) << 56, .fixedWidth(8), [0, 0, 0, 0, 0, 0, 0, 1]),
            (UInt64.max, .fixedWidth(8), [255, 255, 255, 255, 255, 255, 255, 255]),
        ]
    }

    @Test(arguments: fixedWidthTestCasesComplex())
    func fixedWidthTestCasesComplex(testCase: (UInt64, EncodeMethod, [UInt8])) {
        let (value, method, expected) = testCase
        let array = Array(value.encode(method: method))
        #expect(array == expected)
    }

    @Test(arguments: [
        UInt64(0),
        UInt64(1),
        UInt64(2),
        UInt64(1) << 7 - 1,
        UInt64(1) << 7,
        UInt64(1) << 7 + 1,
        UInt64(1) << 14 - 1,
        UInt64(1) << 14,
        UInt64(1) << 14 + 1,
        UInt64(1) << 21 - 1,
        UInt64(1) << 21,
        UInt64(1) << 21 + 1,
        UInt64(1) << 28 - 1,
        UInt64(1) << 28,
        UInt64(1) << 28 + 1,
        UInt64(1) << 35 - 1,
        UInt64(1) << 35,
        UInt64(1) << 35 + 1,
        UInt64(1) << 42 - 1,
        UInt64(1) << 42,
        UInt64(1) << 42 + 1,
        UInt64(1) << 49 - 1,
        UInt64(1) << 49,
        UInt64(1) << 49 + 1,
        UInt64(1) << 56 - 1,
        UInt64(1) << 56,
        UInt64(1) << 56 + 1,
        UInt64(1) << 63 - 1,
        UInt64(1) << 63,
        UInt64(1) << 63 + 1,
        UInt64.max - 1,
        UInt64.max,
    ] as[UInt64])
    func variableWidth(testCase: UInt64) {
        let array = Array(testCase.encode(method: .variableWidth))
        var slice = array[...]
        #expect(slice.decode() == testCase)
    }

    @Test(arguments: [
        UInt64(0),
        UInt64(1),
        UInt64(2),
        UInt64(1) << 32 - 2,
        UInt64(1) << 32 - 1,
        UInt64(1) << 32,
        UInt64(1) << 32 + 2,
        UInt64.max - 2,
        UInt64.max - 1,
        UInt64.max,
    ])
    func fixedWidth(testCase: UInt64) {
        let array = Array(testCase.encode(method: .fixedWidth(8)))
        var slice = array[...]
        #expect(slice.decode(length: 8) == testCase)

        var slice2 = array[...]
        #expect(slice2.decode(length: 4) == testCase & 0xFFFF_FFFF)

        var slice3 = array[...]
        #expect(slice3.decode(length: 2) == testCase & 0xFFFF)
    }

    @Test func multipleDecodes() throws {
        var largeData = Data([254, 254, 254, 254, 254, 254, 254, 254, 254, 254, 254, 254, 254, 254, 254, 254])
        #expect(throws: Error.self) {
            _ = try largeData.decodeUInt64()
        }
        var data = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
        #expect(data.decode(length: 8) as UInt64? == 0x0706_0504_0302_0100)
        #expect(data.decode(length: 4) as UInt32? == 0x0B0A_0908)
        #expect(data.decode(length: 2) as UInt16? == 0x0D0C)
        #expect(data.decode() == 0x0E)
        #expect(data.decode() == 0x0F)
        #expect(data.decode() == nil)
        #expect(data.decode(length: 20) as UInt64? == nil)
        #expect(data.decode(length: -1) as UInt64? == nil)
    }
}
