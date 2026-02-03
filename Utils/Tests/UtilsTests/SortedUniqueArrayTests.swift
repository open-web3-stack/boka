import Foundation
import Testing
@testable import Utils

struct SortedUniqueArrayTests {
    @Test
    func initialization() {
        let array = SortedUniqueArray([3, 1, 2, 3, 5, 4, 2])
        #expect(array.array == [1, 2, 3, 4, 5])

        let sortedArray = try? SortedUniqueArray(sorted: [1, 2, 3, 4, 5])
        #expect(sortedArray?.array == [1, 2, 3, 4, 5])

        let invalidSortedArray = (try? SortedUniqueArray(sorted: [1, 1, 2, 3])) == nil
        #expect(invalidSortedArray)

        let emptyArray = SortedUniqueArray<Int>()
        #expect(emptyArray.array.isEmpty)
    }

    @Test
    func insertion() {
        var array = SortedUniqueArray([1, 3, 5])

        array.insert(2)
        #expect(array.array == [1, 2, 3, 5])

        array.insert(3)
        #expect(array.array == [1, 2, 3, 5])
    }

    @Test
    func removal() {
        var array = SortedUniqueArray([1, 2, 3, 4, 5])

        array.remove(at: 2)
        #expect(array.array == [1, 2, 4, 5])

        array.removeAll()
        #expect(array.array.isEmpty)
    }

    @Test
    func encodingDecoding() throws {
        let array = SortedUniqueArray([1, 2, 3, 4, 5])
        let encodedData = try JSONEncoder().encode(array)
        let decodedArray = try JSONDecoder().decode(SortedUniqueArray<Int>.self, from: encodedData)

        #expect(decodedArray.array == [1, 2, 3, 4, 5])
    }

    @Test
    func appending() {
        var array = SortedUniqueArray([1, 3, 5])
        let otherArray = SortedUniqueArray([2, 4])

        array.append(contentsOf: otherArray)
        #expect(array.array == [1, 2, 3, 4, 5])
    }
}
