import Foundation
import Testing
import Utils

@testable import JAMTests

struct ShuffleTestCase: Codable {
    let input: Int
    let entropy: String
    let output: [Int]
}

struct ShuffleTests {
    static func loadTests() throws -> [ShuffleTestCase] {
        // Load test vectors from the JSON file
        let testData = try TestLoader.getFile(path: "shuffle/shuffle_tests", extension: "json")
        let decoder = JSONDecoder()
        return try decoder.decode([ShuffleTestCase].self, from: testData)
    }

    @Test(arguments: try ShuffleTests.loadTests())
    func testShuffle(testCase: ShuffleTestCase) throws {
        // Create input array [0..<n]
        var input = Array(0 ..< testCase.input)

        // Convert entropy hex string to Data32
        let entropy = Data32(fromHexString: testCase.entropy)!

        // Perform shuffle
        input.shuffle(randomness: entropy)

        // Verify output matches expected
        #expect(input == testCase.output)
    }
}
