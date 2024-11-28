import Codec
import Foundation
import Testing

@testable import Utils

struct LimitedSizeArrayTests {
    struct ConstInt5: ConstInt {
        static let value = 5
    }

    struct ConstInt10: ConstInt {
        static let value = 10
    }

    struct ConstInt0: ConstInt {
        static let value = 0
    }

    @Test func initWithDefaultValue() throws {
        let defaultValue = 1
        let array = LimitedSizeArray<Int, ConstInt5, ConstInt10>(defaultValue: defaultValue)
        #expect(array.array == [1, 1, 1, 1, 1])
        #expect(array.count == 5)
    }

    @Test func expressibleByArrayLiteral() throws {
        let array: LimitedSizeArray<Int, ConstInt5, ConstInt10> = [1, 2, 3, 4, 5]
        #expect(array.array == [1, 2, 3, 4, 5])
    }

    @Test func appendElement() throws {
        var array = LimitedSizeArray<Int, ConstInt5, ConstInt10>([1, 2, 3, 4, 5])
        array.append(6)
        #expect(array.array == [1, 2, 3, 4, 5, 6])
        #expect(array.count == 6)
    }

    @Test func insertElement() throws {
        var array = LimitedSizeArray<Int, ConstInt5, ConstInt10>([1, 2, 3, 4, 5])
        array.insert(0, at: 2)
        #expect(array.array == [1, 2, 0, 3, 4, 5])
        #expect(array.count == 6)
    }

    @Test func removeElement() throws {
        var array = LimitedSizeArray<Int, ConstInt5, ConstInt10>([1, 2, 3, 4, 5, 6])
        let removed = array.remove(at: 2)
        #expect(removed == 3)
        #expect(array.array == [1, 2, 4, 5, 6])
        #expect(array.count == 5)
    }

    @Test func equatable() throws {
        let array1: LimitedSizeArray<Int, ConstInt5, ConstInt10> = [1, 2, 3, 4, 5]
        let array2: LimitedSizeArray<Int, ConstInt5, ConstInt10> = [1, 2, 3, 4, 5]
        let array3: LimitedSizeArray<Int, ConstInt5, ConstInt10> = [5, 4, 3, 2, 1]

        #expect(array1 == array2)
        #expect(array1 != array3)
    }

    @Test func codable() throws {
        let array: LimitedSizeArray<Int, ConstInt5, ConstInt10> = [1, 2, 3, 4, 5]
        let encoded = try JamEncoder.encode(array)
        let decoded = try JamDecoder.decode(LimitedSizeArray<Int, ConstInt5, ConstInt10>.self, from: encoded, withConfig: ())

        #expect(decoded == array)
    }
}
