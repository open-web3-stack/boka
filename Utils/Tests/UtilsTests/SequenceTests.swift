import Foundation
import Testing

@testable import Utils

struct SequenceTests {
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
        [], [1], [2, 4, 5]
    ])
    func isSortedAndUnique(testCase: [Int]) {
        #expect(testCase.isSortedAndUnique())
    }

    @Test(arguments: [
        [], [1], [5, 4, 2]
    ])
    func isSortedAndUniqueBy(testCase: [Int]) {
        #expect(testCase.isSortedAndUnique(by: >))
    }

    @Test(arguments: [
        [1, 1], [2, 1], [2, 3, 4, 4]
    ])
    func notSortedAndUnique(testCase: [Int]) {
        #expect(!testCase.isSortedAndUnique())
    }
}
