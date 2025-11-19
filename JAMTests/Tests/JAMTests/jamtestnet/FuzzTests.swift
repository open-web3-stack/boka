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
        version: "0.7.1",
        filters: [
            // empty to include all
        ],
        ignore: [
            ("0.7.1/1763371098", "00000006"), // tooFewElements (block decode fail, expected to fail)
            ("0.7.1/1763371531", "00000006"), // tooFewElements
            ("0.7.1/1763371531", "00000008"), // tooFewElements
            ("0.7.1/1763371531", "00000011"), // tooFewElements
            ("0.7.1/1763371531", "00000014"), // tooFewElements
            ("0.7.1/1763371531", "00000023"), // tooFewElements
            ("0.7.1/1763371531", "00000028"), // tooFewElements
            ("0.7.1/1763371531", "00000030"), // tooFewElements
            ("0.7.1/1763371531", "00000032"), // tooFewElements
            ("0.7.1/1763371531", "00000038"), // tooFewElements
            ("0.7.1/1763371531", "00000042"), // missing "keyvals": [] in prestate (expected to fail)
            ("0.7.1/1763372314", "00000094"), // tooFewElements
        ]
    ))
    func v071(input: Testcase) async throws {
        try await TraceTest.test(input)
    }
}
