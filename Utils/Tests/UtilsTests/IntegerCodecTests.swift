import Foundation
import Testing

@testable import Utils

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
    func variableWidthTest(testCase: UInt64) {
        let array = Array(testCase.encode(method: .variableWidth))
        var iter = array.makeIterator()
        #expect(iter.decode() == testCase)
    }
}
