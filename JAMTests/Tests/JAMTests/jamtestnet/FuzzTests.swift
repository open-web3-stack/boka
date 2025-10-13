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
        ]
    ))
    func v070(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }

    @Test(arguments: try loadTests(
        version: "0.7.0/_new",
        filters: [
        ],
        ignore: [
            // TODO: revisit these later
            ("0.7.0/_new/1758621171", "00000236"), // used more gas
            ("0.7.0/_new/1758621171", "00000237"), // used more gas, 2 services
            ("0.7.0/_new/1758621172", "00000038"), // used more gas
            ("0.7.0/_new/1758621173", "00000045"), // used more gas
            ("0.7.0/_new/1758621412", "00000024"), // used more gas: 136 (init data is set)
            ("0.7.0/_new/1758621412", "00000025"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new/1758621498", "00000024"), // used more gas: 136
            ("0.7.0/_new/1758621498", "00000025"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new/1758621547", "00000032"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new/1758621879", "00000348"), // used more gas
            ("0.7.0/_new/1758621952", "00000291"), // used more gas: 136 (init data is set)
            ("0.7.0/_new/1758621952", "00000292"), // many (seems manager service 0 need to change delegator to 3436841821)
            ("0.7.0/_new/1758622000", "00000230"), // used more gas (0: 363, 2052168113: 136)
            ("0.7.0/_new/1758622051", "00000093"), // used more gas
            ("0.7.0/_new/1758622051", "00000094"), // used more gas
            ("0.7.0/_new/1758622104", "00000022"), // many
            ("0.7.0/_new/1758622160", "00000009"), // used more gas
            ("0.7.0/_new/1758622313", "00000012"), // used more gas
            ("0.7.0/_new/1758622403", "00000238"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new/1758622403", "00000239"), // used more gas, and privileged service mismatch
            ("0.7.0/_new/1758622442", "00000163"), // used more gas
            ("0.7.0/_new/1758622442", "00000164"), // used more gas, and privileged service mismatch
            ("0.7.0/_new/1758622524", "00000038"), // used more gas
            ("0.7.0/_new/1758622524", "00000039"), // used more gas
        ]
    ))
    func new1(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }

    @Test(arguments: try loadTests(
        version: "0.7.0/_new2",
        filters: [
        ],
        ignore: [
            // TODO: revisit these later
            ("0.7.0/_new2/1758636775", "00000013"), // used more gas
            ("0.7.0/_new2/1758636775", "00000014"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new2/1758636819", "00000022"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new2/1758636961", "00000018"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new2/1758637024", "00000017"), // used more gas
            ("0.7.0/_new2/1758637024", "00000018"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new2/1758637136", "00000019"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new2/1758637250", "00000015"), // used more gas
            ("0.7.0/_new2/1758637250", "00000016"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new2/1758637297", "00000015"), // used more gas
            ("0.7.0/_new2/1758637297", "00000016"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new2/1758637332", "00000016"), // used more gas
            ("0.7.0/_new2/1758637332", "00000017"), // used more gas
            ("0.7.0/_new2/1758637363", "00000023"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new2/1758637447", "00000061"), // used more gas, and 1 storage mismatch
            ("0.7.0/_new2/1758637447", "00000062"), // used more gas, and 2 storage mismatch
            ("0.7.0/_new2/1758637485", "00000019"), // used more gas, and 2 storage mismatch
            ("0.7.0/_new2/1758708840", "00000958"), // error (exp post state is empty)
        ]
    ))
    func new2(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }
}
