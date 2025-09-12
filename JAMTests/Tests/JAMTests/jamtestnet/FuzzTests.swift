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
            ("0.7.0/1756548583", "00000009"), // TODO: find root cause
            ("0.7.0/1757406079", "00000011"), // TODO: account + extra key
            ("0.7.0/1757406516", "00000022"), // TODO: one storage mismatch
            ("0.7.0/1757406558", "00000031"), // TODO: one storage mismatch
            ("0.7.0/1757406558", "00000032"), // TODO: many
            ("0.7.0/1757421101", "00000091"), // TODO: many
            ("0.7.0/1757421824", "00000020"), // TODO: one storage mismatch
            ("0.7.0/1757421824", "00000021"), // TODO: one storage mismatch
            ("0.7.0/1757422206", "00000011"), // TODO: one storage mismatch
        ]
    ))
    func v070(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }
}
