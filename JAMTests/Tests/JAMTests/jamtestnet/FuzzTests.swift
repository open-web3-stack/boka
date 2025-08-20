import Foundation
import Testing
import Utils

@testable import JAMTests

struct FuzzTests {
    struct TestInput {
        let testcase: Testcase
        let allowFailure: Bool

        init(_ testcase: Testcase, allowFailure: Bool = false) {
            self.testcase = testcase
            self.allowFailure = allowFailure
        }
    }

    static func loadTests(
        version: String,
        filters: [(String, String)],
        expectFailure: [(String, String)],
        ignore: [(String, String)]
    ) throws -> [TestInput] {
        let basePath = Bundle.module.resourcePath! + "/fuzz/" + version

        return try FileManager.default.contentsOfDirectory(atPath: basePath)
            .sorted()
            .filter { !$0.starts(with: ".") }
            .flatMap { timestamp -> [TestInput] in
                let path = "\(version)/\(timestamp)"
                let testcases = try JamTestnet.loadTests(path: path, src: .fuzz)
                return testcases
                    .filter { testcase in
                        !ignore.contains { ignorePath, ignorePrefix in
                            path == ignorePath && testcase.description.starts(with: ignorePrefix)
                        }
                    }
                    .filter { testcase in
                        filters.isEmpty || filters.contains { filterPath, filterPrefix in
                            path == filterPath && testcase.description.starts(with: filterPrefix)
                        }
                    }
                    .map { testcase in
                        let allowFailure = expectFailure.contains { failurePath, failurePrefix in
                            path == failurePath && testcase.description.starts(with: failurePrefix)
                        }
                        return TestInput(testcase, allowFailure: allowFailure)
                    }
            }
    }

    @Test(arguments: try loadTests(
        version: "0.6.7",
        filters: [
            // empty to include all
            // example: ("0.6.7/1754982630", "00000004")
            ("0.6.7/1754984893", "00000010"), // state root
            // ("0.6.7/1755083543", "000000"), // state root
            // ("0.6.7/1755530397", "000000"), // state root
            // ("0.6.7/1755531265", "000000"), // state root
        ],
        expectFailure: [
            ("0.6.7/1755252727", "00000011"), // .invalidHeaderWinningTickets
        ],
        ignore: [
            ("0.6.7/1754982087", "000000"), // bad test
            ("0.6.7/1755530535", "00000"), // stats
            ("0.6.7/1755530728", "00000"), // stats
            ("0.6.7/1755530896", "00000"), // stats
            ("0.6.7/1755620371", "00000"), // stats
        ]
    ))
    func v067(_ input: TestInput) async throws {
        try await TraceTest.test(input.testcase, allowFailure: input.allowFailure)
    }
}
