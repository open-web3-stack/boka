import Foundation
import Testing
import Utils

@testable import JAMTests

struct FuzzTests {
    // empty array means run all
    static let testFilters: [(String, String)] = [
        // example: ("0.6.7/1754982630", "00000004")
    ]

    // ignore tests
    static let ignore: [(String, String)] = [
        ("0.6.7/1754725568", "00000004"), // many mismatch (from javajam reports)
        ("0.6.7/1754754058", "00000004"), // many mismatch (from javajam reports)
        ("0.6.7/1754982630", "00000008"), // NOTE: seems this should fail on .invalidResultCodeHash
        ("0.6.7/1755150526", "00000013"), // designate HUH
        ("0.6.7/1755155383", "00000015"), // .invalidResultCodeHash
        ("0.6.7/1755155383", "00000016"), // .invalidResultCodeHash
        ("0.6.7/1755186771", "00000029"), // .invalidResultCodeHash
        ("0.6.7/1755190301", "00000008"), // .invalidResultCodeHash
    ]

    static func loadTests(version: String) throws -> [Testcase] {
        let basePath = Bundle.module.resourcePath! + "/fuzz/" + version
        var allTestcases: [Testcase] = []

        for timestamp in try FileManager.default.contentsOfDirectory(atPath: basePath).sorted() {
            guard !timestamp.starts(with: ".") else { continue }

            let path = "\(version)/\(timestamp)"

            let testcases = try JamTestnet.loadTests(path: path, src: .fuzz)

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

        return allTestcases
    }

    @Test(arguments: try loadTests(version: "0.6.7"))
    func fuzzTestsv067(_ testcase: Testcase) async throws {
        try await TraceTest.test(testcase)
    }
}
