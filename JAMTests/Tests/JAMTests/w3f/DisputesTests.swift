import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

struct DisputesState: Equatable, Codable, Disputes {
    var judgements: JudgementsState
    var reports: ConfigFixedSizeArray<
        ReportItem?,
        ProtocolConfig.TotalNumberOfCores
    >
    var timeslot: TimeslotIndex
    var currentValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    var previousValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >

    mutating func mergeWith(postState: DisputesPostState) {
        judgements = postState.judgements
        reports = postState.reports
    }
}

struct DisputesTestcase: Codable {
    var input: ExtrinsicDisputes
    var preState: DisputesState
    var output: Either<[Ed25519PublicKey], UInt8>
    var postState: DisputesState
}

struct DisputesTests {
    static func loadTests(variant: TestVariants) throws -> [Testcase] {
        try TestLoader.getTestcases(path: "disputes/\(variant)", extension: "bin")
    }

    func disputesTests(_ testcase: Testcase, variant: TestVariants) throws {
        let config = variant.config
        let decoder = JamDecoder(data: testcase.data, config: config)
        let testcase = try decoder.decode(DisputesTestcase.self)

        var state = testcase.preState
        let result = Result {
            try testcase.input.validate(config: config)
            return try state.update(
                config: config,
                disputes: testcase.input
            )
        }
        switch result {
        case let .success((postState, offenders)):
            switch testcase.output {
            case let .left(output):
                state.mergeWith(postState: postState)
                #expect(state == testcase.postState)
                #expect(offenders == output)
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

    @Test(arguments: try DisputesTests.loadTests(variant: .tiny))
    func tinyTests(_ testcase: Testcase) throws {
        try disputesTests(testcase, variant: .tiny)
    }

    @Test(arguments: try DisputesTests.loadTests(variant: .full))
    func fullTests(_ testcase: Testcase) throws {
        try disputesTests(testcase, variant: .full)
    }
}
