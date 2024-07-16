import Foundation
import Testing

@testable import Utils

struct ArrayTests {
    @Test(arguments: [
        [], [1], [2, 4], [5, 19, 34, 34, 56, 56],
    ])
    func isSorted(testCase: [Int]) {
        #expect(testCase.isSorted())
    }

    @Test(arguments: [
        [], [1], [4, 2], [56, 56, 34, 34, 19, 5]
    ])
    func isSortedBy(testCase: [Int]) {
        #expect(testCase.isSorted(by: >))
    }

    @Test(arguments: [
        [4, 2], [56, 56, 34, 35, 19, 5], [1, 3, 2]
    ])
    func notSorted(testCase: [Int]) {
        #expect(!testCase.isSorted())
    }

    @Test(arguments: [
        ([], []),
        ([], [1]),
        ([1], []),
        ([1, 2, 3], [1, 2, 3]),
        ([1, 10, 20, 30], [2, 12, 22, 32, 42]),
        ([1, 2, 3], [4, 5, 6]),
        ([4, 5, 6], [1, 2, 3]),
        ([1, 5, 10, 30], [6, 7, 8, 9, 10, 11]),
    ])
    func insertSorted(testCase: ([Int], [Int])) {
        var arr = testCase.0
        arr.insertSorted(testCase.1)
        #expect(arr.isSorted())
        #expect(arr == (testCase.0 + testCase.1).sorted())
    }

    @Test(arguments: [
        ([3, 3, 2, 2, 1, 1], [3, 2, 1]),
        ([6, 5, 4], [4, 3, 2]),
        ([10, 5, 3, 2], [11, 10, 4, 3, 3, 2, 1]),
    ])
    func insertSortedBy(testCase: ([Int], [Int])) {
        var arr = testCase.0
        arr.insertSorted(testCase.1, by: >)
        #expect(arr.isSorted(by: >))
        #expect(arr == (testCase.0 + testCase.1).sorted(by: >))
    }
}
