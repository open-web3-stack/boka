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

    @Test(.disabled(), arguments: try loadTests(
        version: "0.7.1",
        filters: [
            // empty to include all
        ],
        ignore: [
            ("0.7.1/1763487981", "00000050"), // missing "keyvals": [] in prestate (expected to fail)
            ("0.7.1/1763488328", "00000050"), // missing "keyvals": [] in prestate (expected to fail)
        ]
    ))
    func v071(input: Testcase) async throws {
        try await TraceTest.test(input, config: TestVariants.full.config)
    }
}
