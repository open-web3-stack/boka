@testable import func Blockchain.outsideInReorder
import Testing

struct SafroleTests {
    @Test(arguments: [
        (
            [], [],
        ),
        (
            [1], [1],
        ),
        (
            [1, 2, 3], [1, 3, 2],
        ),
        (
            [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], [1, 10, 2, 9, 3, 8, 4, 7, 5, 6],
        ),
    ])
    func outsideInReorder(testCase: ([Int], [Int])) {
        let (arr, expected) = testCase
        #expect(Blockchain.outsideInReorder(arr) == expected)
    }
}
