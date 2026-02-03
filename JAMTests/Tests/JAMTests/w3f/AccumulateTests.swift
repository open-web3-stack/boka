import Blockchain
import Codec
import Foundation
@testable import JAMTests
import Testing
import TracingUtils
import Utils

private let logger = Logger(label: "AccumulateTests")

private struct AccumulateInput: Codable {
    var timeslot: TimeslotIndex
    var reports: [WorkReport]
}

private struct PreimageMapEntry: Codable, Equatable {
    var hash: Data32
    var blob: Data
}

private struct PreimageRequestKey: Codable, Equatable {
    var hash: Data32
    var length: DataLength
}

private struct PreimageRequestMapEntry: Codable, Equatable {
    var key: PreimageRequestKey
    var value: StateKeys.ServiceAccountPreimageInfoKey.Value
}

private struct StorageMapEntry: Codable, Equatable {
    var key: Data
    var value: Data
}

private struct Account: Codable, Equatable {
    var service: ServiceAccountDetails
    var storage: [StorageMapEntry]
    var preimagesBlobs: [PreimageMapEntry]
    var preimageRequests: [PreimageRequestMapEntry]
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
        ProtocolConfig.EpochLength,
    >
    var accumulationHistory: ConfigFixedSizeArray<
        SortedUniqueArray<Data32>,
        ProtocolConfig.EpochLength,
    >
    var privilegedServices: PrivilegedServices
    var serviceStatistics: [ServiceStatisticsMapEntry]
    var accounts: [AccountsMapEntry]
}

private enum Output: Codable {
    case ok(Data32)
    case err(UInt8)

    private enum CodingKeys: String, CodingKey {
        case ok
        case err
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let variant = try container.decode(UInt8.self)
        switch variant {
        case 0:
            self = try .ok(container.decode(Data32.self))
        case 1:
            self = try .err(container.decode(UInt8.self))
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "invalid output variant \(variant)",
                ),
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        switch self {
        case let .ok(data):
            try container.encode(UInt8(0))
            try container.encode(data)
        case let .err(code):
            try container.encode(UInt8(1))
            try container.encode(code)
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
        ProtocolConfig.TotalNumberOfCores,
    >
    var accumulationQueue: StateKeys.AccumulationQueueKey.Value
    var accumulationHistory: StateKeys.AccumulationHistoryKey.Value

    var accounts: [ServiceIndex: ServiceAccountDetails] = [:]
    var storages: [ServiceIndex: [Data: Data]] = [:]
    var preimages: [ServiceIndex: [Data32: Data]] = [:]
    var preimageInfo: [ServiceIndex: [HashAndLength: StateKeys.ServiceAccountPreimageInfoKey.Value]] = [:]

    func copy() -> ServiceAccounts {
        self
    }

    func get(serviceAccount index: ServiceIndex) async throws -> ServiceAccountDetails? {
        accounts[index]
    }

    func get(serviceAccount index: ServiceIndex, storageKey key: Data) async throws -> Data? {
        storages[index]?[key]
    }

    func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32) async throws -> Data? {
        preimages[index]?[hash]
    }

    func get(
        serviceAccount index: ServiceIndex,
        preimageHash hash: Data32,
        length: UInt32,
    ) async throws -> StateKeys.ServiceAccountPreimageInfoKey.Value? {
        preimageInfo[index]?[HashAndLength(hash: hash, length: length)]
    }

    func historicalLookup(serviceAccount _: ServiceIndex, timeslot _: TimeslotIndex, preimageHash _: Data32) async throws -> Data? {
        nil
    }

    mutating func set(serviceAccount index: ServiceIndex, account: ServiceAccountDetails?) {
        accounts[index] = account
    }

    mutating func set(serviceAccount index: ServiceIndex, storageKey key: Data, value: Data?) {
        // update footprint
        let oldValue = storages[index]?[key]
        logger.debug("storage footprint before: \(accounts[index]?.itemsCount ?? 0) items, \(accounts[index]?.totalByteLength ?? 0) bytes")
        accounts[index]?.updateFootprintStorage(key: key, oldValue: oldValue, newValue: value)
        logger.debug("storage footprint after: \(accounts[index]?.itemsCount ?? 0) items, \(accounts[index]?.totalByteLength ?? 0) bytes")

        // update value
        storages[index, default: [:]][key] = value
    }

    mutating func set(serviceAccount index: ServiceIndex, preimageHash hash: Data32, value: Data?) {
        preimages[index, default: [:]][hash] = value
    }

    mutating func set(
        serviceAccount index: ServiceIndex,
        preimageHash hash: Data32,
        length: UInt32,
        value: StateKeys.ServiceAccountPreimageInfoKey.Value?,
    ) {
        let key = HashAndLength(hash: hash, length: length)
        // update footprint
        let oldValue = preimageInfo[index]?[key]
        logger.debug("preimage footprint before: \(accounts[index]?.itemsCount ?? 0) items, \(accounts[index]?.totalByteLength ?? 0) bytes")
        accounts[index]?.updateFootprintPreimage(oldValue: oldValue, newValue: value, length: length)
        logger.debug("preimage footprint after: \(accounts[index]?.itemsCount ?? 0) items, \(accounts[index]?.totalByteLength ?? 0) bytes")

        // update value
        preimageInfo[index, default: [:]][key] = value
    }

    mutating func remove(serviceAccount index: ServiceIndex) async throws {
        accounts[index] = nil
        storages[index] = nil
        preimages[index] = nil
        preimageInfo[index] = nil
    }
}

struct AccumulateTests {
    static func loadTests(variant: TestVariants) throws -> [Testcase] {
        try TestLoader.getTestcases(path: "stf/accumulate/\(variant)", extension: "bin")
    }

    func accumulateTests(_ testcase: Testcase, variant: TestVariants) async throws {
        // setupTestLogger()

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
            accumulationHistory: preState.accumulationHistory,
        )

        for entry in testcase.preState.accounts {
            fullState.accounts[entry.index] = entry.data.service
            for storage in entry.data.storage {
                fullState.storages[entry.index, default: [:]][storage.key] = storage.value
            }
            for preimage in entry.data.preimagesBlobs {
                fullState.preimages[entry.index, default: [:]][preimage.hash] = preimage.blob
            }
            for preimageRequest in entry.data.preimageRequests {
                let key = HashAndLength(hash: preimageRequest.key.hash, length: preimageRequest.key.length)
                fullState.preimageInfo[entry.index, default: [:]][key] = preimageRequest.value
            }
        }

        let result = await Result {
            try await fullState.update(
                config: config,
                availableReports: testcase.input.reports,
                timeslot: testcase.input.timeslot,
                prevTimeslot: preState.timeslot,
                entropy: preState.entropy,
            )
        }

        switch result {
        case let .success(content):
            switch testcase.output {
            case let .ok(expectedRoot):
                // NOTE: timeslot and entropy are not changed by accumulate
                #expect(content.root == expectedRoot, "accumulate root mismatch")
                #expect(fullState.accumulationQueue == testcase.postState.accumulationQueue, "AccumulationQueue mismatch")
                #expect(fullState.accumulationHistory == testcase.postState.accumulationHistory, "AccumulationHistory mismatch")
                #expect(fullState.privilegedServices == testcase.postState.privilegedServices, "PrivilegedServices mismatch")
                #expect(fullState.accounts.count == testcase.postState.accounts.count, "Accounts count mismatch")
                for entry in testcase.postState.accounts {
                    let account = fullState.accounts[entry.index]!
                    #expect(account == entry.data.service, "ServiceAccountDetail mismatch")
                    for storage in entry.data.storage {
                        #expect(fullState.storages[entry.index]?[storage.key] == storage.value, "Storage mismatch")
                    }
                    for preimage in entry.data.preimagesBlobs {
                        #expect(fullState.preimages[entry.index]?[preimage.hash] == preimage.blob, "Preimage mismatch")
                    }
                    for preimageRequest in entry.data.preimageRequests {
                        let key = HashAndLength(hash: preimageRequest.key.hash, length: preimageRequest.key.length)
                        #expect(
                            fullState.preimageInfo[entry.index]?[key] == preimageRequest.value,
                            "Preimage request mismatch",
                        )
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
        try await accumulateTests(testcase, variant: .tiny)
    }

    @Test(arguments: try AccumulateTests.loadTests(variant: .full))
    func fullTests(_ testcase: Testcase) async throws {
        try await accumulateTests(testcase, variant: .full)
    }
}
