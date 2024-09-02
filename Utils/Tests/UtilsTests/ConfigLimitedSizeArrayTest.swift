import Codec
import Foundation
import Testing

@testable import Utils

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

struct ConfigLimitedSizeArrayTests {
    @Test func initWithDefaultValue() throws {
        let config = 0
        let defaultValue = 1
        let array = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, defaultValue: defaultValue)
        #expect(array.array == [1, 1, 1])
        #expect(array.count == 3)
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

    // TODO: Codable
    // @Test func codable() throws {
    //     let config = 0
    //     let array = try ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>(config: config, array: [1, 2, 3])
    //     let encoded = try JamEncoder.encode(array)
    //     let decoded = try JamDecoder.decode(ConfigLimitedSizeArray<Int, MinLength3, MaxLength5>.self, from: encoded, withConfig: config)
    //     #expect(decoded == array)
    // }
}
