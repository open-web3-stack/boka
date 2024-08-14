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
    static func loadTests() throws -> [TrieTestCase] {
        let tests = try TestLoader.getTestFiles(path: "trie", extension: "json")
        return try tests.map {
            let data = try Data(contentsOf: URL(fileURLWithPath: $0.path))
            let decoder = JSONDecoder()
            return try decoder.decode(TrieTestCase.self, from: data)
        }
    }

    @Test(arguments: try loadTests())
    func trieTests(_ testcase: TrieTestCase) throws {
        for element in testcase {
            let kv = element.input.reduce(into: [Data32: Data]()) { result, entry in
                let keyData = Data(fromHexString: entry.key)
                let valueData = Data(fromHexString: entry.value)
                result[Data32(keyData!)!] = valueData
            }

            let result = try stateMerklize(kv: kv)
            #expect(result.data.toHexString() == element.output)
        }
    }
}
