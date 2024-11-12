import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

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

struct RecentHisoryTestcase: Codable {
    var input: RecentHistoryInput
    var preState: RecentHistory
    var postState: RecentHistory
}

struct RecentHistoryTests {
    static func loadTests() throws -> [Testcase] {
        try TestLoader.getTestcases(path: "history/data", extension: "bin")
    }

    @Test(arguments: try loadTests())
    func recentHistory(_ testcase: Testcase) throws {
        let config = ProtocolConfigRef.mainnet
        let testcase = try JamDecoder.decode(RecentHisoryTestcase.self, from: testcase.data, withConfig: config)

        var state = testcase.preState
        state.update(
            headerHash: testcase.input.headerHash,
            parentStateRoot: testcase.input.parentStateRoot,
            accumulateRoot: testcase.input.accumulateRoot,
            lookup: Dictionary(uniqueKeysWithValues: testcase.input.workPackages.map { (
                $0.hash,
                $0.exportsRoot
            ) })
        )

        #expect(state == testcase.postState)
    }
}
