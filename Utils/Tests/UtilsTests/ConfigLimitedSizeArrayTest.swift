import Codec
import Foundation
import Testing
@testable import Utils

struct MinLengthNegated: ReadInt {
    typealias TConfig = Int

    static func read(config _: Int) -> Int {
        -1
    }
}

struct MinLength3: ReadInt {
    typealias TConfig = Int

    static func read(config _: Int) -> Int {
        3
    }
}

struct MaxLength5: ReadInt {
    typealias TConfig = Int

    static func read(config _: Int) -> Int {
        5
    }
}

struct MaxLength8: ReadInt {
    typealias TConfig = Int

    static func read(config _: Int) -> Int {
        8
    }
}

struct ConfigLimitedSizeArrayTests {
    @Test func initWithDefaultValue() throws {
        let config = 0
        let defaultValue = 1
        var array = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, defaultValue: defaultValue)
        #expect(array.array == [1, 1, 1])
        #expect(array.count == 3)
        #expect(array[0] == 1)
        array[0] = 0
        #expect(array[0] != 1)
    }

    @Test func initWithArrayWithinBounds() throws {
        let config = 0
        let array = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [1, 2, 3])
        #expect(array.array == [1, 2, 3])
        #expect(array.count == 3)
    }

    @Test func initWithArrayOutOfBounds() throws {
        let config = 0
        // Array smaller than min length
        #expect(throws: ConfigLimitedSizeArrayError.tooFewElements) {
            _ = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [1, 2])
        }

        // Array larger than max length
        #expect(throws: ConfigLimitedSizeArrayError.tooManyElements) {
            _ = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [1, 2, 3, 4, 5, 6])
        }
    }

    @Test func appendElement() throws {
        let config = 0
        var array = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [1, 2, 3])
        try array.append(4)
        #expect(array.array == [1, 2, 3, 4])
        #expect(array.count == 4)

        // Appending beyond max length
        #expect(throws: ConfigLimitedSizeArrayError.tooManyElements) {
            try array.append(5)
            try array.append(6)
        }
    }

    @Test func safeAppendElement() throws {
        let config = 0
        var array = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [1, 2, 3])
        array.safeAppend(4)
        #expect(array.array == [1, 2, 3, 4])
        #expect(array.count == 4)

        // Safe append when max length is reached
        array.safeAppend(5)
        array.safeAppend(6)
        #expect(array.array == [2, 3, 4, 5, 6])
        #expect(array.count == 5)
    }

    @Test func insertElement() throws {
        let config = 0
        var array = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [1, 2, 3])
        try array.insert(0, at: 1)
        #expect(array.array == [1, 0, 2, 3])
        #expect(array.count == 4)

        // Inserting beyond max length
        #expect(throws: ConfigLimitedSizeArrayError.tooManyElements) {
            try array.insert(5, at: 0)
            try array.insert(6, at: 0)
        }

        // Inserting at invalid index
        #expect(throws: ConfigLimitedSizeArrayError.invalidIndex) {
            try array.insert(7, at: -1)
        }

        #expect(throws: ConfigLimitedSizeArrayError.invalidIndex) {
            try array.insert(8, at: 10)
        }
    }

    @Test func removeElement() throws {
        let config = 0
        var array = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [1, 2, 3, 4])
        let removed = try array.remove(at: 2)
        #expect(removed == 3)
        #expect(array.array == [1, 2, 4])
        #expect(array.count == 3)

        // Removing below min length
        #expect(throws: ConfigLimitedSizeArrayError.tooFewElements) {
            _ = try array.remove(at: 0)
            _ = try array.remove(at: 0)
        }

        // Removing at invalid index
        #expect(throws: ConfigLimitedSizeArrayError.invalidIndex) {
            _ = try array.remove(at: -1)
        }

        #expect(throws: ConfigLimitedSizeArrayError.invalidIndex) {
            _ = try array.remove(at: 10)
        }
    }

    @Test func equatable() throws {
        let config = 0
        let array1 = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [1, 2, 3])
        let array2 = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [1, 2, 3])
        let array3 = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [3, 2, 1])

        #expect(array1 == array2)
        #expect(array1 != array3)
    }

    @Test func codable() throws {
        let config = 0
        let array = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [1, 2, 3])
        let encoded = try JamEncoder.encode(array)
        let decoded = try JamDecoder.decode(ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>.self, from: encoded, withConfig: config)
        #expect(decoded == array)
    }

    @Test func throwLength() throws {
        #expect(throws: Error.self) {
            _ = try ConfigLimitedSizeArray<Int, MinLengthNegated, MaxLength5>(config: 0, array: [1, 2, 3])
        }
        #expect(throws: Error.self) {
            _ = try ConfigLimitedSizeArray<Int, MaxLength5, MinLength3>(config: 0, array: [1, 2, 3])
        }
    }

    @Test func randomAccessCollection() throws {
        let value = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength8>(config: 0, array: [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(value.startIndex == 0)
        #expect(value.endIndex == 8)

        var idx = value.startIndex
        value.formIndex(after: &idx)
        #expect(idx == 1)

        value.formIndex(before: &idx)
        #expect(idx == 0)

        let dist = value.distance(from: 0, to: 7)
        #expect(dist == 7)

        let indexForward = value.index(0, offsetBy: 3)
        #expect(indexForward == 3)

        let indexWithinLimit = value.index(0, offsetBy: 3, limitedBy: 5)
        #expect(indexWithinLimit == 3)
        #expect(try value.index(after: #require(indexWithinLimit)) == 4)
        #expect(try value.index(before: #require(indexWithinLimit)) == 2)
        #expect(try value.index(from: #require(indexWithinLimit)) == 3)
    }

    @Test func description() throws {
        let config = 0
        let array = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [1, 2, 3, 4, 5])
        #expect(array.description == "[1, 2, 3, 4, 5]")
        #expect(array.debugDescription == "ConfigLimitedSizeArray<Int, 3, 5>([1, 2, 3, 4, 5])")
    }
}
