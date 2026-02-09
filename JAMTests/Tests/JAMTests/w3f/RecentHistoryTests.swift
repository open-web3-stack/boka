import Blockchain
import Codec
import Foundation
@testable import JAMTests
import Testing
import Utils

struct ReportedWorkPackage: Codable {
    var hash: Data32
    var exportsRoot: Data32
}

struct RecentHistoryInput: Codable {
    var headerHash: Data32
    var parentStateRoot: Data32
    var accumulateRoot: Data32
    var workPackages: [ReportedWorkPackage]
}

struct RecentHistoryTestcase: Codable {
    var input: RecentHistoryInput
    var preState: RecentHistory
    var postState: RecentHistory
}

struct RecentHistoryTests {
    static func loadTests(variant: TestVariants) throws -> [Testcase] {
        try TestLoader.getTestcases(path: "stf/history/\(variant)", extension: "bin")
    }

    func recentHistory(_ testcase: Testcase, variant: TestVariants) throws {
        let config = variant.config
        let testcase = try JamDecoder.decode(RecentHistoryTestcase.self, from: testcase.data, withConfig: config)

        var state = testcase.preState
        state.updatePartial(
            parentStateRoot: testcase.input.parentStateRoot,
        )
        state.update(
            headerHash: testcase.input.headerHash,
            accumulateRoot: testcase.input.accumulateRoot,
            lookup: Dictionary(uniqueKeysWithValues: testcase.input.workPackages.map { (
                $0.hash,
                $0.exportsRoot,
            ) }),
        )

        #expect(state == testcase.postState)
    }

    @Test(arguments: try RecentHistoryTests.loadTests(variant: .tiny))
    func tinyTests(_ testcase: Testcase) throws {
        try recentHistory(testcase, variant: .tiny)
    }

    @Test(arguments: try RecentHistoryTests.loadTests(variant: .full))
    func fullTests(_ testcase: Testcase) throws {
        try recentHistory(testcase, variant: .full)
    }
}
