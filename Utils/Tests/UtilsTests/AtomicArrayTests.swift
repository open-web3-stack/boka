import Foundation
import Testing

@testable import Utils

struct AtomicArrayTests {
    @Test func initArray() throws {
        let array = AtomicArray<Int>(repeating: 1, count: 5)
        #expect(array.getArray() == [1, 1, 1, 1, 1])
        #expect(array.count == 5)
    }

    @Test func appendElement() throws {
        var array = AtomicArray<Int>([1, 2, 3, 4, 5])
        array.append(6)
        #expect(array.getArray() == [1, 2, 3, 4, 5, 6])
        #expect(array.count == 6)
    }

    @Test func insertElement() throws {
        var array = AtomicArray<Int>([1, 2, 3, 4, 5])
        array.insert(0, at: 2)
        #expect(array.getArray() == [1, 2, 0, 3, 4, 5])
        #expect(array.count == 6)
    }

    @Test func removeElement() throws {
        var array = AtomicArray<Int>([1, 2, 3, 4, 5, 6])
        let removed = array.remove(at: 2)
        #expect(removed == 3)
        #expect(array.getArray() == [1, 2, 4, 5, 6])
        #expect(array.count == 5)
    }

    @Test func equatable() throws {
        let array1 = AtomicArray<Int>([1, 2, 3, 4, 5])
        let array2 = AtomicArray<Int>([1, 2, 3, 4, 5])
        let array3 = AtomicArray<Int>([5, 4, 3, 2, 1])

        #expect(array1 == array2)
        #expect(array1 != array3)
    }
}
