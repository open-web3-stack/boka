import Foundation
@testable import JAMTests
import Testing
import Utils

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
        let decoder = JSONDecoder()
        let testcase = try decoder.decode(TrieTestCase.self, from: testcase.data)
        for element in testcase {
            let kv = element.input.reduce(into: [Data31: Data]()) { result, entry in
                let keyData = Data(fromHexString: entry.key)
                let valueData = Data(fromHexString: entry.value)
                result[Data31(keyData![relative: 0 ..< 31])!] = valueData
            }

            let result = try stateMerklize(kv: kv)
            #expect(result.data.toHexString() == element.output)
        }
    }
}
