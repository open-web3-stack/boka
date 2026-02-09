import Testing
@testable import Utils

struct CollectionUtilsTests {
    @Test func atMethods() throws {
        let array = [1, 2, 3, 4, 5]

        let result1 = try array.at(relative: 2...)
        #expect(result1 == [3, 4, 5])

        let result2 = try array.at(relative: ..<3)
        #expect(result2 == [1, 2, 3])

        let result3 = try array.at(relative: ..<0)
        #expect(result3.isEmpty)

        #expect(throws: Error.self) {
            _ = try array.at(relative: ..<6)
        }

        let result4 = try array.at(relative: ...3)
        #expect(result4 == [1, 2, 3, 4])

        let result5 = try array.at(relative: ...0)
        #expect(result5 == [1])
        #expect(throws: Error.self) {
            _ = try array.at(0 ..< 6)
        }
    }

    @Test func safeIndexAccess() {
        let array = [10, 20, 30, 40, 50]

        #expect(array[safe: 0] == 10)
        #expect(array[safe: 4] == 50)
        #expect(array[safe: 5] == nil)
        #expect(array[safe: -1] == nil)
    }

    @Test func safeRangeAccess() {
        let array = [10, 20, 30, 40, 50]

        #expect(array[safe: 0 ..< 2] == [10, 20])
        #expect(array[safeRelative: 3 ..< 6] == nil)
        #expect(array[safe: 2 ..< 2] == [])
    }

    @Test func indexAccess() throws {
        let array = [10, 20, 30, 40, 50]

        let element = try array.at(2)
        #expect(element == 30)
        #expect(throws: Error.self) {
            _ = try array.at(5)
        }
    }

    @Test func relativeIndexAccess() {
        let array = [10, 20, 30, 40, 50]
        #expect(array[relative: 1] == 20)
    }

    @Test func relativeRangeAccess() {
        let array = [10, 20, 30, 40, 50]

        #expect(array[relative: 0 ..< 2] == [10, 20])
        #expect(array[relative: 3 ..< 5] == [40, 50])
        #expect(array[relative: 1...] == [20, 30, 40, 50])
        #expect(array[relative: ...4] == [10, 20, 30, 40, 50])
    }

    @Test func safeRelativeIndexAccess() {
        let array = [10, 20, 30, 40, 50]

        #expect(array[safeRelative: 1] == 20)
        #expect(array[safeRelative: -1] == nil)
        #expect(array[safeRelative: 10] == nil)
    }

    @Test func atRelativeIndexAccess() throws {
        let array = [10, 20, 30, 40, 50]
        let element = try array.at(relative: 2)
        #expect(element == 30)
        #expect(throws: Error.self) {
            _ = try array.at(relative: 10)
        }
    }
}
