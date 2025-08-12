import Foundation
import Testing
import Utils

@testable import JAMTests

struct OtherTests {
    /// empty dict means run all tests
    static let testFilters: [String: String] = [
        "0.6.7/1754582958": "00000003",
        // "0.6.7/1754724115": "00000003", // ServiceAccountDetail Mismatch (maybe new or transfer related)
        // "0.6.7/1754725568": "00000003", // ServiceAccountDetail Mismatch (maybe new or transfer related)
        "0.6.7/1754753264": "00000001",
        // "0.6.7/1754982087": "00000005", // ServiceAccountDetail Mismatch (maybe new or transfer related)
        // "0.6.7/1754982630": "00000008", // many mismatch
    ]

    static func discoverTests() throws -> [Testcase] {
        let otherPath = Bundle.module.resourcePath! + "/other"
        var allTestcases: [Testcase] = []

        for version in try FileManager.default.contentsOfDirectory(atPath: otherPath).sorted() {
            guard !version.starts(with: ".") else { continue }

            let versionPath = otherPath + "/" + version
            for seed in try FileManager.default.contentsOfDirectory(atPath: versionPath).sorted() {
                guard !seed.starts(with: ".") else { continue }

                let path = "\(version)/\(seed)"
                let testcases = try JamTestnet.loadTests(path: path, src: .other)

                if testFilters.isEmpty {
                    allTestcases.append(contentsOf: testcases)
                } else if let filterPrefix = testFilters[path] {
                    let filteredTestcases = testcases.filter { $0.description.starts(with: filterPrefix) }
                    allTestcases.append(contentsOf: filteredTestcases)
                }
            }
        }

        return allTestcases
    }

    @Test(arguments: try discoverTests())
    func otherTests(_ testcase: Testcase) async throws {
        try await TraceTest.test(testcase)
    }
}
