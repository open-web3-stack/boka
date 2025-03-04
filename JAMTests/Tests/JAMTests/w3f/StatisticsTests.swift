import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

struct StatisticsState: Equatable, Codable, ActivityStatistics {
    var activityStatistics: ValidatorActivityStatistics
    var timeslot: TimeslotIndex
    var currentValidators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
}

struct StatisticsInput: Codable {
    var timeslot: TimeslotIndex
    var author: ValidatorIndex
    var extrinsic: Extrinsic
}

struct StatisticsTestcase: Codable {
    var input: StatisticsInput
    var preState: StatisticsState
    var postState: StatisticsState
}

struct StatisticsTests {
    static func loadTests(variant: TestVariants) throws -> [Testcase] {
        try TestLoader.getTestcases(path: "statistics/\(variant)", extension: "bin")
    }

    func statisticsTests(_ testcase: Testcase, variant: TestVariants) throws {
        let config = variant.config
        let decoder = JamDecoder(data: testcase.data, config: config)
        let testcase = try decoder.decode(StatisticsTestcase.self)

        var state = testcase.preState
        let result = try state.update(
            config: config,
            newTimeslot: testcase.input.timeslot,
            extrinsic: testcase.input.extrinsic,
            authorIndex: testcase.input.author
        )
        state.activityStatistics = result

        #expect(state == testcase.postState)
    }

    @Test(arguments: try StatisticsTests.loadTests(variant: .tiny))
    func tinyTests(_ testcase: Testcase) throws {
        try statisticsTests(testcase, variant: .tiny)
    }

    @Test(arguments: try StatisticsTests.loadTests(variant: .full))
    func fullTests(_ testcase: Testcase) throws {
        try statisticsTests(testcase, variant: .full)
    }
}
