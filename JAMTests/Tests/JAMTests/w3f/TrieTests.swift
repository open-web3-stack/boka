import Foundation
import Testing
import Utils

@testable import JAMTests

struct TrieElement: Codable {
    let input: [String: String]
    let output: String
}

typealias TrieTestCase = [TrieElement]

struct TrieTests {
    static func loadTests() throws -> [Testcase] {
        try TestLoader.getTestcases(path: "trie", extension: "json")
    }

    @Test(arguments: try loadTests())
    func trieTests(_ testcase: Testcase) throws {
        withKnownIssue("TODO: outdated key type", isIntermittent: true) {
            let decoder = JSONDecoder()
            let testcase = try decoder.decode(TrieTestCase.self, from: testcase.data)
            for element in testcase {
                let kv = element.input.reduce(into: [Data31: Data]()) { _, entry in
                    let keyData = Data(fromHexString: entry.key)
                    let valueData = Data(fromHexString: entry.value)
                    // result[Data31(keyData!)!] = valueData
                }

                let result = try stateMerklize(kv: kv)
                #expect(result.data.toHexString() == element.output)
            }
        }
    }
}
