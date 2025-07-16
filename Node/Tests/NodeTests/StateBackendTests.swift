import Blockchain
import Database
import Foundation
import Testing
import Utils

@testable import Node

enum BackendType: String, CaseIterable {
    case inMemory = "InMemoryBackend"
    case rocksDB = "RocksDBBackend"

    func createBackend() async throws -> StateBackendProtocol {
        switch self {
        case .inMemory:
            return InMemoryBackend()
        case .rocksDB:
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let config = ProtocolConfigRef.dev
            let genesisBlock = BlockRef.dummy(config: config)
            return try await RocksDBBackend(path: tempDir, config: config, genesisBlock: genesisBlock, genesisStateData: [:])
        }
    }
}

struct StateBackendTests {
    @Test(arguments: BackendType.allCases)
    func testGetKeysBasic(backendType: BackendType) async throws {
        let backend = try await backendType.createBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())

        let prefixA = Data([0xAA])
        let prefixB = Data([0xBB])

        let testPairs: [(Data31, Data)] = [
            (Data31(prefixA + Data([0x01]) + Data(repeating: 0, count: 29))!, Data("valueA1".utf8)),
            (Data31(prefixA + Data([0x02]) + Data(repeating: 0, count: 29))!, Data("valueA2".utf8)),
            (Data31(prefixA + Data([0x03]) + Data(repeating: 0, count: 29))!, Data("valueA3".utf8)),

            (Data31(prefixB + Data([0x01]) + Data(repeating: 0, count: 29))!, Data("valueB1".utf8)),
            (Data31(prefixB + Data([0x02]) + Data(repeating: 0, count: 29))!, Data("valueB2".utf8)),

            (Data31(Data([0x01]) + Data(repeating: 0, count: 30))!, Data("value1".utf8)),
            (Data31(Data([0x02]) + Data(repeating: 0, count: 30))!, Data("value2".utf8)),
        ]

        // Write test data
        for (key, value) in testPairs {
            try await stateBackend.writeRaw([(key: key, value: value)])
        }

        // Test: Get all keys
        let allKeys = try await stateBackend.getKeys(nil, nil, nil)
        #expect(allKeys.count == testPairs.count, "[\(backendType.rawValue)] Should return all \(testPairs.count) keys")

        for (expectedKey, expectedValue) in testPairs {
            let found = allKeys.first { $0.key == expectedKey.data }
            #expect(found != nil, "[\(backendType.rawValue)] Key \(expectedKey.toHexString()) should be found")
            #expect(found?.value == expectedValue, "[\(backendType.rawValue)] Value should match for key \(expectedKey.toHexString())")
        }

        // Test: Prefix filtering
        let prefixAResults = try await stateBackend.getKeys(prefixA, nil, nil)
        #expect(prefixAResults.count == 3, "[\(backendType.rawValue)] Should find 3 keys with prefix A")

        for result in prefixAResults {
            #expect(result.key.starts(with: prefixA), "[\(backendType.rawValue)] All results should have prefix A")
        }

        let prefixBResults = try await stateBackend.getKeys(prefixB, nil, nil)
        #expect(prefixBResults.count == 2, "[\(backendType.rawValue)] Should find 2 keys with prefix B")

        for result in prefixBResults {
            #expect(result.key.starts(with: prefixB), "[\(backendType.rawValue)] All results should have prefix B")
        }

        // Test: Start key filtering
        let startKey = Data31(Data([0x05]) + Data(repeating: 0, count: 30))!
        let startKeyResults = try await stateBackend.getKeys(nil, startKey, nil)

        // Should find keys >= 0x05, which are the 0xAA and 0xBB prefixed keys (5 total)
        #expect(
            startKeyResults.count == 5,
            "[\(backendType.rawValue)] Should get exactly 5 keys starting from 0x05 (AA and BB prefixed keys)"
        )

        for result in startKeyResults {
            let isSmaller = result.key.lexicographicallyPrecedes(startKey.data)
            #expect(!isSmaller, "[\(backendType.rawValue)] All keys should be >= start key (0x05)")
        }

        // Test: Limit
        let limitedKeys = try await stateBackend.getKeys(nil, nil, 3)
        #expect(limitedKeys.count == 3, "[\(backendType.rawValue)] Should respect the limit of 3")

        // Test: Combined prefix and limit
        let prefixLimitedResults = try await stateBackend.getKeys(prefixA, nil, 2)
        #expect(prefixLimitedResults.count == 2, "[\(backendType.rawValue)] Should respect both prefix and limit")

        for result in prefixLimitedResults {
            #expect(result.key.starts(with: prefixA), "[\(backendType.rawValue)] All results should have prefix A")
        }
    }

    @Test(arguments: BackendType.allCases)
    func testGetKeysLargeBatch(backendType: BackendType) async throws {
        let backend = try await backendType.createBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())

        let keyCount = 1500
        var expectedKeys: Set<Data> = []

        // Use a specific prefix to avoid any potential conflicts
        let batchPrefix = Data([0xFF])

        for i in 0 ..< keyCount {
            var keyData = Data(repeating: 0, count: 31)
            keyData[0] = batchPrefix[0]
            keyData[1] = UInt8(i % 256)
            keyData[2] = UInt8(i / 256)

            let key = Data31(keyData)!
            let value = Data("batchValue\(i)".utf8)

            try await stateBackend.writeRaw([(key: key, value: value)])
            expectedKeys.insert(key.data)
        }

        // Test: Get all keys with the batch prefix
        let results = try await stateBackend.getKeys(batchPrefix, nil, nil)
        let resultKeys = Set(results.map(\.key))

        #expect(results.count == keyCount, "[\(backendType.rawValue)] Should return all \(keyCount) batch keys")
        #expect(resultKeys == expectedKeys, "[\(backendType.rawValue)] Should return exactly the expected batch keys")

        // Test: Large batch with limit
        let limitedResults = try await stateBackend.getKeys(batchPrefix, nil, 100)
        #expect(limitedResults.count == 100, "[\(backendType.rawValue)] Should respect limit of 100 for large batch")

        // Test: Large batch with startKey
        let midKey = Data31(Data([0xFF, 128, 0]) + Data(repeating: 0, count: 28))!
        let startKeyResults = try await stateBackend.getKeys(batchPrefix, midKey, nil)

        // Should get roughly half the results (keys >= midKey)
        #expect(startKeyResults.count > 0, "[\(backendType.rawValue)] Should get some results with startKey in large batch")
        #expect(startKeyResults.count < keyCount, "[\(backendType.rawValue)] Should get less than total with startKey filter")

        for result in startKeyResults {
            let isSmaller = result.key.lexicographicallyPrecedes(midKey.data)
            #expect(!isSmaller, "[\(backendType.rawValue)] All results should be >= startKey in large batch")
        }
    }
}
