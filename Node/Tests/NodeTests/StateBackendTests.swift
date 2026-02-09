import Blockchain
import Database
import Foundation
@testable import Node
import Testing
import Utils

enum BackendType: String, CaseIterable {
    case inMemory = "InMemoryBackend"
    case rocksDB = "RocksDBBackend"
}

final class StateBackendTests {
    let basePath = {
        let tmpDir = FileManager.default.temporaryDirectory
        return tmpDir.appendingPathComponent("\(UUID().uuidString)")
    }()

    let config: ProtocolConfigRef = .dev
    let genesisBlock: BlockRef

    init() async throws {
        genesisBlock = BlockRef.dummy(config: config)
    }

    deinit {
        try? FileManager.default.removeItem(at: basePath)
    }

    func createBackend(_ backendType: BackendType, testIndex: Int = 0) async throws -> StateBackendProtocol {
        switch backendType {
        case .inMemory:
            return InMemoryBackend()
        case .rocksDB:
            let testPath = basePath.appendingPathComponent("test_\(testIndex)")
            return try await RocksDBBackend(
                path: testPath,
                config: config,
                genesisBlock: genesisBlock,
                genesisStateData: [:],
            )
        }
    }

    @Test(arguments: BackendType.allCases)
    func getKeysBasic(backendType: BackendType) async throws {
        let backend = try await createBackend(backendType, testIndex: 1)
        let stateBackend = StateBackend(backend, config: config, rootHash: Data32())

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
        #expect(allKeys.count == testPairs.count)

        for (expectedKey, expectedValue) in testPairs {
            let found = allKeys.first { $0.key == expectedKey.data }
            #expect(found != nil)
            #expect(found?.value == expectedValue)
        }

        // Test: Prefix filtering
        let prefixAResults = try await stateBackend.getKeys(prefixA, nil, nil)
        #expect(prefixAResults.count == 3)

        for result in prefixAResults {
            #expect(result.key.starts(with: prefixA))
        }

        let prefixBResults = try await stateBackend.getKeys(prefixB, nil, nil)
        #expect(prefixBResults.count == 2)

        for result in prefixBResults {
            #expect(result.key.starts(with: prefixB))
        }

        // Test: Start key filtering
        let startKey = Data31(Data([0x05]) + Data(repeating: 0, count: 30))!
        let startKeyResults = try await stateBackend.getKeys(nil, startKey, nil)

        // Should find keys >= 0x05, which are the 0xAA and 0xBB prefixed keys (5 total)
        #expect(
            startKeyResults.count == 5,
        )

        for result in startKeyResults {
            let isSmaller = result.key.lexicographicallyPrecedes(startKey.data)
            #expect(!isSmaller)
        }

        // Test: Limit
        let limitedKeys = try await stateBackend.getKeys(nil, nil, 3)
        #expect(limitedKeys.count == 3)

        // Test: Combined prefix and limit
        let prefixLimitedResults = try await stateBackend.getKeys(prefixA, nil, 2)
        #expect(prefixLimitedResults.count == 2)

        for result in prefixLimitedResults {
            #expect(result.key.starts(with: prefixA))
        }
    }

    @Test(arguments: BackendType.allCases)
    func getKeysLargeBatch(backendType: BackendType) async throws {
        let backend = try await createBackend(backendType, testIndex: 2)
        let stateBackend = StateBackend(backend, config: config, rootHash: Data32())

        let keyCount = 1500
        var expectedKeys: Set<Data> = []

        // Use a specific prefix to avoid any potential conflicts
        let batchPrefix = Data([0xFF])

        for i in 0 ..< keyCount {
            var keyData = Data(repeating: 0, count: 31)
            keyData[0] = batchPrefix[0]
            keyData[1] = UInt8(i % 256)
            keyData[2] = UInt8(i / 256)

            let key = try #require(Data31(keyData))
            let value = Data("batchValue\(i)".utf8)

            try await stateBackend.writeRaw([(key: key, value: value)])
            expectedKeys.insert(key.data)
        }

        // Test: Get all keys with the batch prefix
        let results = try await stateBackend.getKeys(batchPrefix, nil, nil)
        let resultKeys = Set(results.map(\.key))

        #expect(results.count == keyCount)
        #expect(resultKeys == expectedKeys)

        // Test: Large batch with limit
        let limitedResults = try await stateBackend.getKeys(batchPrefix, nil, 100)
        #expect(limitedResults.count == 100)

        // Test: Large batch with startKey
        let midKey = Data31(Data([0xFF, 128, 0]) + Data(repeating: 0, count: 28))!
        let startKeyResults = try await stateBackend.getKeys(batchPrefix, midKey, nil)

        // Should get roughly half the results (keys >= midKey)
        #expect(startKeyResults.count > 0)
        #expect(startKeyResults.count < keyCount)

        for result in startKeyResults {
            let isSmaller = result.key.lexicographicallyPrecedes(midKey.data)
            #expect(!isSmaller)
        }
    }
}
