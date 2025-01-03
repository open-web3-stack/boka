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
        try array.append(6)
        #expect(array.array == [1, 2, 3, 4, 5, 6])
        #expect(array.count == 6)
    }

    @Test func insertElement() throws {
        var array = LimitedSizeArray<Int, ConstInt5, ConstInt10>([1, 2, 3, 4, 5])
        try array.insert(0, at: 2)
        #expect(array.array == [1, 2, 0, 3, 4, 5])
        #expect(array.count == 6)
    }

    @Test func removeElement() throws {
        var array = LimitedSizeArray<Int, ConstInt5, ConstInt10>([1, 2, 3, 4, 5, 6])
        let removed = try array.remove(at: 2)
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

    @Test func encodedSize() throws {
        struct FixedEncodedSizeType: EncodedSize {
            var encodedSize: Int { 4 }
            static var encodeedSizeHint: Int? { 4 }
        }

        let array: LimitedSizeArray<FixedEncodedSizeType, ConstInt5, ConstInt5> = .init(
            Array(repeating: FixedEncodedSizeType(), count: 5)
        )

        #expect(array.encodedSize == 20) // 5 elements * 4 bytes each
        let array1: LimitedSizeArray<FixedEncodedSizeType, ConstInt5, ConstInt10> = .init(
            Array(repeating: FixedEncodedSizeType(), count: 10)
        )
        #expect(array1.encodedSize == 41)
        #expect(LimitedSizeArray<FixedEncodedSizeType, ConstInt5, ConstInt5>.encodeedSizeHint == 20)
        #expect(LimitedSizeArray<FixedEncodedSizeType, ConstInt5, ConstInt10>.encodeedSizeHint == nil)
    }

    @Test func randomAccessCollection() throws {
        var array: LimitedSizeArray<Int, ConstInt5, ConstInt10> = [1, 2, 3, 4, 5]

        #expect(array.startIndex == 0)
        #expect(array.endIndex == 5)
        #expect(array[array.startIndex] == 1)
        #expect(array[array.index(array.startIndex, offsetBy: 2)] == 3)

        var iteratorIndex = array.startIndex
        array.formIndex(after: &iteratorIndex)
        #expect(iteratorIndex == 1)
        array.formIndex(before: &iteratorIndex)
        #expect(iteratorIndex == 0)
        #expect(array.index(after: iteratorIndex) == array.index(before: iteratorIndex) + 2)
        array[iteratorIndex] = 9
        #expect(array[iteratorIndex] == 9)
        #expect(array.index(from: iteratorIndex) == 0)
    }

    @Test func randomAccessCollectionIndexOutOfBounds() throws {
        let array: LimitedSizeArray<Int, ConstInt5, ConstInt10> = [1, 2, 3, 4, 5]

        // Ensure accessing out of bounds throws as expected
        let index = array.startIndex
        let outOfBounds = array.index(array.endIndex, offsetBy: 1, limitedBy: array.endIndex)
        #expect(outOfBounds == nil)
        #expect(index.distance(to: array.endIndex) == array.count)
    }
}
