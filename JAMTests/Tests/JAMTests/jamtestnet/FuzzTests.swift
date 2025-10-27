import Foundation
import Testing
import Utils

@testable import JAMTests

struct FuzzTests {
    static func loadTests(
        version: String,
        filters: [(String, String)],
        ignore: [(String, String)]
    ) throws -> [Testcase] {
        let basePath = Bundle.module.resourcePath! + "/fuzz/" + version

        return try FileManager.default.contentsOfDirectory(atPath: basePath)
            .sorted()
            .filter { !$0.starts(with: ".") }
            .flatMap { timestamp -> [Testcase] in
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
            }
    }

    @Test(arguments: try loadTests(
        version: "0.7.0",
        filters: [
            // empty to include all
            // example: ("0.7.0/1754982630", "00000004")
        ],
        ignore: [
            // NOTE: most 0.7.0 ones are fixed except some privileged service related mismatches which are changed in 0.7.1+
            ("0.7.0/1758622403", "00000239"), // privileged service mismatch
            ("0.7.0/1758622442", "00000164"), // privileged service mismatch
            ("0.7.0/1758621952", "00000292"), // many (seems manager service 0 need to change delegator to 3436841821)
            ("0.7.0/1758622104", "00000022"), // many
            ("0.7.0/1758708840", "00000958"), // error (exp post state is empty)
        ]
    ))
    func v070(_: Testcase) async throws {
        // try await TraceTest.test(input)
    }
}
