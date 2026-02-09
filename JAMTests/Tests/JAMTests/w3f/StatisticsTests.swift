import Blockchain
import Codec
import Foundation
@testable import JAMTests
import Testing
import Utils

/// NOTE: the statistics tests only test the validator stats
struct TestStatsState: Equatable, Codable {
    var current: ConfigFixedSizeArray<Statistics.Validator, ProtocolConfig.TotalNumberOfValidators>
    var previous: ConfigFixedSizeArray<Statistics.Validator, ProtocolConfig.TotalNumberOfValidators>
    var timeslot: TimeslotIndex
    var currentValidators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
}

struct StatsInput: Codable {
    var timeslot: TimeslotIndex
    var author: ValidatorIndex
    var extrinsic: Extrinsic
}

struct StatsTestcase: Codable {
    var input: StatsInput
    var preState: TestStatsState
    var postState: TestStatsState
}

struct StatsState: ActivityStatistics {
    var activityStatistics: Statistics
    var timeslot: TimeslotIndex
    var currentValidators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
}

struct StatisticsTests {
    static func loadTests(variant: TestVariants) throws -> [Testcase] {
        try TestLoader.getTestcases(path: "stf/statistics/\(variant)", extension: "bin")
    }

    func statisticsTests(_ testcase: Testcase, variant: TestVariants) throws {
        let config = variant.config
        let decoder = JamDecoder(data: testcase.data, config: config)
        let testcase = try decoder.decode(StatsTestcase.self)

        var testStatsState = testcase.preState

        let reporters = Set(
            testcase.input.extrinsic.reports.guarantees.flatMap { guarantee in
                guarantee.credential.map { credential in
                    testStatsState.currentValidators[Int(credential.index)].ed25519
                }
            },
        )
        var activityStatistics = Statistics.dummy(config: config)
        activityStatistics.accumulator = testStatsState.current
        activityStatistics.previous = testStatsState.previous
        let fullStatsState = StatsState(
            activityStatistics: activityStatistics,
            timeslot: testStatsState.timeslot,
            currentValidators: testStatsState.currentValidators,
        )
        let result = try fullStatsState.update(
            config: config,
            newTimeslot: testcase.input.timeslot,
            extrinsic: testcase.input.extrinsic,
            reporters: Array(reporters),
            authorIndex: testcase.input.author,
            availableReports: [],
            accumulateStats: [:],
        )
        testStatsState.current = result.accumulator
        testStatsState.previous = result.previous

        #expect(testStatsState == testcase.postState)
    }

    @Test(arguments: try StatisticsTests.loadTests(variant: .tiny))
    func tinyTests(_ testcase: Testcase) throws {
        try statisticsTests(testcase, variant: .tiny)
    }

    @Test(arguments: try StatisticsTests.loadTests(variant: .full))
    func fullTests(_ testcase: Testcase) {
        withKnownIssue("outdated testcase, missing reporters", isIntermittent: true) {
            try statisticsTests(testcase, variant: .full)
        }
    }
}
