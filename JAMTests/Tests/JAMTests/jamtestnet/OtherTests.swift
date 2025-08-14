import Foundation
import Testing
import Utils

@testable import JAMTests

struct OtherTests {
    // empty array means run all
    static let testFilters: [(String, String)] = []

    // ignore tests
    static let ignore: [(String, String)] = [
        ("0.6.7/1754982630", "00000008"), // NOTE: seems this should fail on .invalidResultCodeHash
    ]

    static func discoverTests() throws -> [Testcase] {
        let otherPath = Bundle.module.resourcePath! + "/other"
        var allTestcases: [Testcase] = []

        for version in try FileManager.default.contentsOfDirectory(atPath: otherPath).sorted() {
            guard !version.starts(with: ".") else { continue }

            let versionPath = otherPath + "/" + version
            for timestamp in try FileManager.default.contentsOfDirectory(atPath: versionPath).sorted() {
                guard !timestamp.starts(with: ".") else { continue }

                let path = "\(version)/\(timestamp)"

                let testcases = try JamTestnet.loadTests(path: path, src: .other)

                let testsExceptIgnore = testcases.filter { testcase in
                    for (ignorePath, prefix) in ignore where path == ignorePath && testcase.description.starts(with: prefix) {
                        return false
                    }
                    return true
                }

                if testFilters.isEmpty {
                    allTestcases.append(contentsOf: testsExceptIgnore)
                } else {
                    for (filterPath, filterPrefix) in testFilters where filterPath == path {
                        let filtered = testsExceptIgnore.filter { $0.description.starts(with: filterPrefix) }
                        allTestcases.append(contentsOf: filtered)
                    }
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
