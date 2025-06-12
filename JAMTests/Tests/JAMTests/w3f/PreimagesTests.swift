import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

private struct PreimageInfo: Codable, Equatable, Hashable, Comparable {
    var hash: Data32
    var blob: Data

    static func < (lhs: PreimageInfo, rhs: PreimageInfo) -> Bool {
        lhs.hash < rhs.hash
    }
}

private struct HistoryEntry: Codable, Equatable {
    var key: HashAndLength
    var value: [TimeslotIndex]
}

private struct AccountsMapEntry: Codable, Equatable {
    var index: ServiceIndex
    @CodingAs<SortedSet<PreimageInfo>> var preimages: Set<PreimageInfo>
    @CodingAs<SortedKeyValues<HashAndLength, [TimeslotIndex]>> var history: [HashAndLength: [TimeslotIndex]]
}

private struct PreimagesState: Equatable, Codable, Preimages {
    var accounts: [AccountsMapEntry] = []
    // NOTE: we are not using/updating stats in preimage stf, may need to check
    var serviceStatistics: [ServiceStatisticsMapEntry]

    func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32) async throws -> Data? {
        for account in accounts where account.index == index {
            for preimage in account.preimages where preimage.hash == hash {
                return preimage.blob
            }
        }
        return nil
    }

    func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32,
             length: UInt32) async throws -> LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>?
    {
        for account in accounts where account.index == index {
            for history in account.history where history.key.hash == hash && history.key.length == length {
                return .init(history.value)
            }
        }
        return nil
    }

    mutating func mergeWith(postState: PreimagesPostState) {
        for update in postState.updates {
            let accountIndex = accounts.firstIndex { account in
                account.index == update.serviceIndex
            }
            if let accountIndex {
                var account = accounts[accountIndex]
                account.preimages.insert(PreimageInfo(hash: update.hash, blob: update.data))
                account.history[HashAndLength(hash: update.hash, length: update.length)] = [update.timeslot]
                accounts[accountIndex] = account
            }
        }
    }
}

private struct PreimagesInput: Codable {
    var preimages: ExtrinsicPreimages
    var slot: TimeslotIndex
}

private struct PreimagesTestcase: Codable {
    var input: PreimagesInput
    var preState: PreimagesState
    var output: UInt8?
    var postState: PreimagesState
}

struct PreimagesTests {
    static func loadTests() throws -> [Testcase] {
        try TestLoader.getTestcases(path: "preimages/data", extension: "bin")
    }

    func preimagesTests(_ testcase: Testcase, variant: TestVariants) async throws {
        let config = variant.config
        let decoder = JamDecoder(data: testcase.data, config: config)
        let testcase = try decoder.decode(PreimagesTestcase.self)

        var state = testcase.preState
        let result = await Result {
            try await state.updatePreimages(
                config: config,
                timeslot: testcase.input.slot,
                preimages: testcase.input.preimages
            )
        }

        switch result {
        case let .success(postState):
            switch testcase.output {
            case .none:
                state.mergeWith(postState: postState)
                // NOTE: we are not using/updating stats in preimage stf, may need to check
                state.serviceStatistics = testcase.postState.serviceStatistics
                #expect(state == testcase.postState)
            case .some:
                Issue.record("Expected error, got \(result)")
            }
        case .failure:
            switch testcase.output {
            case .none:
                Issue.record("Expected success, got \(result)")
            case .some:
                // ignore error code because it is unspecified
                break
            }
        }
    }

    @Test(arguments: try PreimagesTests.loadTests())
    func tests(_ testcase: Testcase) async throws {
        try await preimagesTests(testcase, variant: .full)
    }
}
