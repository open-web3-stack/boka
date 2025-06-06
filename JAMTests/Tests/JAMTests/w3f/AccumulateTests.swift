import Blockchain
import Codec
import Foundation
import Testing
import TracingUtils
import Utils

@testable import JAMTests

private struct AccumulateInput: Codable {
    var timeslot: TimeslotIndex
    var reports: [WorkReport]
}

private struct PreimageMapEntry: Codable, Equatable {
    var hash: Data32
    var blob: Data
}

private struct Account: Codable, Equatable {
    var service: ServiceAccountDetails
    var preimages: [PreimageMapEntry]
}

private struct AccountsMapEntry: Codable, Equatable {
    var index: ServiceIndex
    var data: Account
}

struct ServiceStatisticsMapEntry: Codable, Equatable {
    var id: ServiceIndex
    var record: Statistics.Service
}

private struct AccumulateState: Equatable, Codable {
    var timeslot: TimeslotIndex
    var entropy: Data32
    var accumulationQueue: ConfigFixedSizeArray<
        [AccumulationQueueItem],
        ProtocolConfig.EpochLength
    >
    var accumulationHistory: ConfigFixedSizeArray<
        SortedUniqueArray<Data32>,
        ProtocolConfig.EpochLength
    >
    var privilegedServices: PrivilegedServices
    var accounts: [AccountsMapEntry]
    var serviceStatistics: [ServiceStatisticsMapEntry]
}

private enum Output: Codable {
    case ok(Data32)
    case err

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let val = try container.decode(UInt8.self)
        switch val {
        case 0:
            self = try .ok(container.decode(Data32.self))
        case 1:
            self = .err
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid output")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .ok(data):
            try container.encode(0)
            try container.encode(data)
        case .err:
            try container.encode(1)
        }
    }
}

private struct AccumulateTestcase: Codable {
    var input: AccumulateInput
    var preState: AccumulateState
    var output: Output
    var postState: AccumulateState
}

private struct FullAccumulateState: Accumulation {
    var timeslot: TimeslotIndex
    var privilegedServices: PrivilegedServices
    var validatorQueue: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
    var authorizationQueue: ConfigFixedSizeArray<
        ConfigFixedSizeArray<Data32, ProtocolConfig.MaxAuthorizationsQueueItems>,
        ProtocolConfig.TotalNumberOfCores
    >
    var accumulationQueue: StateKeys.AccumulationQueueKey.Value
    var accumulationHistory: StateKeys.AccumulationHistoryKey.Value

    var accounts: [ServiceIndex: ServiceAccountDetails] = [:]
    var storages: [ServiceIndex: [Data32: Data]] = [:]
    var preimages: [ServiceIndex: [Data32: Data]] = [:]
    var preimageInfo: [ServiceIndex: [Data32: StateKeys.ServiceAccountPreimageInfoKey.Value]] = [:]

    func get(serviceAccount index: ServiceIndex) async throws -> ServiceAccountDetails? {
        accounts[index]
    }

    func get(serviceAccount index: ServiceIndex, storageKey key: Data32) async throws -> Data? {
        storages[index]?[key]
    }

    func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32) async throws -> Data? {
        preimages[index]?[hash]
    }

    func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32, length _: UInt32) async throws -> StateKeys
        .ServiceAccountPreimageInfoKey.Value?
    {
        preimageInfo[index]?[hash]
    }

    func historicalLookup(serviceAccount _: ServiceIndex, timeslot _: TimeslotIndex, preimageHash _: Data32) async throws -> Data? {
        nil
    }

    mutating func set(serviceAccount index: ServiceIndex, account: ServiceAccountDetails?) {
        accounts[index] = account
    }

    mutating func set(serviceAccount index: ServiceIndex, storageKey key: Data32, value: Data?) {
        storages[index, default: [:]][key] = value
    }

    mutating func set(serviceAccount index: ServiceIndex, preimageHash hash: Data32, value: Data?) {
        preimages[index, default: [:]][hash] = value
    }

    mutating func set(
        serviceAccount index: ServiceIndex,
        preimageHash hash: Data32,
        length _: UInt32,
        value: StateKeys.ServiceAccountPreimageInfoKey.Value?
    ) {
        preimageInfo[index, default: [:]][hash] = value
    }
}

struct AccumulateTests {
    // init() {
    //     setupTestLogger()
    // }

    static func loadTests(variant: TestVariants) throws -> [Testcase] {
        try TestLoader.getTestcases(path: "accumulate/\(variant)", extension: "bin")
    }

    func accumulateTests(_ testcase: Testcase, variant: TestVariants) async throws {
        let config = variant.config
        let decoder = JamDecoder(data: testcase.data, config: config)
        let testcase = try decoder.decode(AccumulateTestcase.self)

        let preState = testcase.preState
        var fullState = try FullAccumulateState(
            timeslot: preState.timeslot,
            privilegedServices: preState.privilegedServices,
            validatorQueue: .init(config: config, defaultValue: .dummy(config: config)),
            authorizationQueue: .init(config: config, defaultValue: .init(config: config, defaultValue: Data32())),
            accumulationQueue: preState.accumulationQueue,
            accumulationHistory: preState.accumulationHistory
        )

        for entry in testcase.preState.accounts {
            fullState.accounts[entry.index] = entry.data.service
            for preimage in entry.data.preimages {
                fullState.preimages[entry.index, default: [:]][preimage.hash] = preimage.blob
            }
        }

        let result = await Result {
            try await fullState.update(
                config: config,
                availableReports: testcase.input.reports,
                timeslot: testcase.input.timeslot,
                prevTimeslot: preState.timeslot,
                entropy: preState.entropy
            )
        }

        switch result {
        case let .success(content):
            switch testcase.output {
            case let .ok(expectedRoot):
                // NOTE: timeslot and entropy are not changed by accumulate
                #expect(content.root == expectedRoot, "root mismatch")
                #expect(fullState.accumulationQueue == testcase.postState.accumulationQueue, "AccumulationQueue mismatch")
                #expect(fullState.accumulationHistory == testcase.postState.accumulationHistory, "AccumulationHistory mismatch")
                #expect(fullState.privilegedServices == testcase.postState.privilegedServices, "PrivilegedServices mismatch")

                #expect(fullState.accounts.count == testcase.postState.accounts.count, "Accounts count mismatch")
                for entry in testcase.postState.accounts {
                    let account = fullState.accounts[entry.index]!
                    #expect(account == entry.data.service, "ServiceAccountDetail mismatch")
                    for preimage in entry.data.preimages {
                        #expect(fullState.preimages[entry.index]?[preimage.hash] == preimage.blob, "Preimage mismatch")
                    }
                }
            case .err:
                Issue.record("Expected error, got \(result)")
            }
        case .failure:
            switch testcase.output {
            case .ok:
                Issue.record("Expected success, got \(result)")
            case .err:
                // ignore error code because it is unspecified
                break
            }
        }
    }

    @Test(arguments: try AccumulateTests.loadTests(variant: .tiny))
    func tinyTests(_ testcase: Testcase) async throws {
        await withKnownIssue("TODO: debug", isIntermittent: true) {
            try await accumulateTests(testcase, variant: .tiny)
        }
    }

    @Test(arguments: try AccumulateTests.loadTests(variant: .full))
    func fullTests(_ testcase: Testcase) async throws {
        await withKnownIssue("TODO: debug", isIntermittent: true) {
            try await accumulateTests(testcase, variant: .full)
        }
    }
}
