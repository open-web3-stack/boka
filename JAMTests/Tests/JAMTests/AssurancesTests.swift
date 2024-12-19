import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

struct AssurancesInput: Codable {
    var assurances: ExtrinsicAvailability
    var timeslot: TimeslotIndex
    var parentHash: Data32
}

struct AssuranceState: Equatable, Codable, Assurances {
    var reports: ConfigFixedSizeArray<ReportItem?, ProtocolConfig.TotalNumberOfCores>
    var currentValidators:
        ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
}

struct AssurancesTestcase: Codable {
    var input: AssurancesInput
    var preState: AssuranceState
    var output: Either<[WorkReport], UInt8>
    var postState: AssuranceState
}

enum AssurancesTestVariants: String, CaseIterable {
    case tiny
    case full

    var config: ProtocolConfigRef {
        switch self {
        case .tiny:
            ProtocolConfigRef.tiny
        case .full:
            ProtocolConfigRef.mainnet
        }
    }
}

struct AssurancesTests {
    static func loadTests(variant: AssurancesTestVariants) throws -> [Testcase] {
        try TestLoader.getTestcases(path: "assurances/\(variant)", extension: "bin")
    }

    func assurancesTests(_ testcase: Testcase, variant: AssurancesTestVariants) throws {
        let config = variant.config
        let decoder = JamDecoder(data: testcase.data, config: config)
        let testcase = try decoder.decode(AssurancesTestcase.self)

        var state = testcase.preState
        let result = Result {
            try testcase.input.assurances.validate(config: config)
            return try state.update(
                config: config, timeslot: testcase.input.timeslot,
                extrinsic: testcase.input.assurances,
                parentHash: testcase.input.parentHash
            )
        }
        switch result {
        case let .success((newReports, availableReports)):
            switch testcase.output {
            case let .left(reports):
                state.reports = newReports
                #expect(state == testcase.postState)
                #expect(availableReports == reports)
            case .right:
                Issue.record("Expected error, got \(result)")
            }
        case .failure:
            switch testcase.output {
            case .left:
                Issue.record("Expected success, got \(result)")
            case .right:
                // ignore error code because it is unspecified
                break
            }
        }
    }

    @Test(arguments: try AssurancesTests.loadTests(variant: .tiny))
    func tinyTests(_ testcase: Testcase) throws {
        try assurancesTests(testcase, variant: .tiny)
    }

    @Test(arguments: try AssurancesTests.loadTests(variant: .full))
    func fullTests(_ testcase: Testcase) throws {
        try assurancesTests(testcase, variant: .full)
    }
}
