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
                            path == ignorePath && testcase.description.contains(ignorePrefix)
                        }
                    }
                    .filter { testcase in
                        filters.isEmpty || filters.contains { filterPath, filterPrefix in
                            path == filterPath && testcase.description.contains(filterPrefix)
                        }
                    }
            }
    }

    @Test(arguments: try loadTests(
        version: "0.7.2",
        filters: [
        ],
        ignore: [
        ]
    ))
    func v072(input: Testcase) async throws {
        try await TraceTest.test(input, config: TestVariants.tiny.config)
    }
}
