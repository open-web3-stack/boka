import Codec
import Foundation
import Testing

@testable import Utils

struct SortedArrayTests {
    @Test
    func initWithUnsortedArray() {
        let unsorted = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5]
        let sorted = SortedArray(unsorted)
        #expect(sorted.array == [1, 1, 2, 3, 3, 4, 5, 5, 5, 6, 9])
    }

    @Test
    func initWithSortedArray() throws {
        let sorted = try SortedArray(sorted: [1, 2, 3, 4, 5])
        #expect(sorted.array == [1, 2, 3, 4, 5])
    }

    @Test
    func initWithSortedArrayThrowsOnUnsortedInput() {
        #expect(throws: SortedContainerError.invalidData) {
            try SortedArray(sorted: [3, 1, 4, 1, 5])
        }
    }

    @Test
    func initWithSortedUnchecked() {
        let sorted = SortedArray(sortedUnchecked: [1, 2, 3, 4, 5])
        #expect(sorted.array == [1, 2, 3, 4, 5])
    }

    @Test
    func insertElement() {
        var sorted = SortedArray([1, 3, 5])
        sorted.insert(4)
        #expect(sorted.array == [1, 3, 4, 5])
    }

    @Test
    func appendContentsOfCollection() {
        var sorted = SortedArray([1, 3, 5])
        sorted.append(contentsOf: [2, 4, 6])
        #expect(sorted.array == [1, 2, 3, 4, 5, 6])
    }

    @Test
    func appendContentsOfSortedArray() {
        var sorted1 = SortedArray([1, 3, 5])
        let sorted2 = SortedArray([2, 4, 6])
        sorted1.append(contentsOf: sorted2)
        #expect(sorted1.array == [1, 2, 3, 4, 5, 6])
    }

    @Test
    func removeAtIndex() {
        var sorted = SortedArray([1, 2, 3, 4, 5])
        sorted.remove(at: 2)
        #expect(sorted.array == [1, 2, 4, 5])
    }

    @Test
    func countProperty() {
        let sorted = SortedArray([1, 2, 3, 4, 5])
        #expect(sorted.count == 5)
    }

    @Test
    func encodingAndDecoding() throws {
        let original = SortedArray([3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5])
        let encoded = try JamEncoder.encode(original)

        let decoder = JamDecoder(data: encoded)
        let decoded = try decoder.decode(SortedArray<Int>.self)

        #expect(original.array == decoded.array)
    }

    @Test
    func insertIndex() {
        let sorted = SortedArray([1, 3, 5, 7, 9])
        #expect(sorted.insertIndex(0) == 0)
        #expect(sorted.insertIndex(2) == 1)
        #expect(sorted.insertIndex(4) == 2)
        #expect(sorted.insertIndex(6) == 3)
        #expect(sorted.insertIndex(8) == 4)
        #expect(sorted.insertIndex(10) == 5)
    }

    @Test
    func insertIndexWithRange() {
        let sorted = SortedArray([1, 3, 5, 7, 9])
        #expect(sorted.insertIndex(5, begin: 1, end: 3) == 2)
    }
}
