import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

struct RecentHistoryInput: Codable {
    var headerHash: Data32
    var parentStateRoot: Data32
    var accumulateRoot: Data32
    var workPackages: [Data32]
}

struct RecentHisoryTestcase: Codable {
    var input: RecentHistoryInput
    var preState: RecentHistory
    var postState: RecentHistory
}

struct RecentHistoryTests {
    static func loadTests() throws -> [Testcase] {
        try TestLoader.getTestcases(path: "history/data", extension: "scale")
    }

    @Test(arguments: try loadTests())
    func recentHistory(_ testcase: Testcase) throws {
        let config = ProtocolConfigRef.mainnet
        let testcase = try JamDecoder.decode(RecentHisoryTestcase.self, from: testcase.data, withConfig: config)

        var state = testcase.preState
        try state.update(
            headerHash: testcase.input.headerHash,
            parentStateRoot: testcase.input.parentStateRoot,
            accumulateRoot: testcase.input.accumulateRoot,
            workReportHashes: ConfigLimitedSizeArray(config: config, array: testcase.input.workPackages)
        )

        #expect(state == testcase.postState)
    }
}
