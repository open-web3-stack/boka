import Foundation
import Testing
import Utils

@testable import Blockchain

struct StateBackendTests {
    @Test
    func testGetKeysEmpty() async throws {
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())

        let keys = try await stateBackend.getKeys(nil, nil, nil)
        #expect(keys.isEmpty, "Empty state should return no keys")
    }

    @Test
    func testGetKeysBasic() async throws {
        let backend = InMemoryBackend()
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

        for (key, value) in testPairs {
            try await stateBackend.writeRaw([(key: key, value: value)])
        }

        let allKeys = try await stateBackend.getKeys(nil, nil, nil)
        #expect(allKeys.count == testPairs.count, "Should return all \(testPairs.count) keys")

        for (expectedKey, expectedValue) in testPairs {
            let found = allKeys.first { $0.key == expectedKey.data }
            #expect(found != nil, "Key \(expectedKey.toHexString()) should be found")
            #expect(found?.value == expectedValue, "Value should match for key \(expectedKey.toHexString())")
        }

        let limitedKeys = try await stateBackend.getKeys(nil, nil, 3)
        #expect(limitedKeys.count == 3, "Should respect the limit of 3")

        let prefixAResults = try await stateBackend.getKeys(prefixA, nil, nil)
        #expect(prefixAResults.count == 3, "Should find 3 keys with prefix A")

        for result in prefixAResults {
            #expect(result.key.starts(with: prefixA), "All results should have prefix A")
        }

        let prefixBResults = try await stateBackend.getKeys(prefixB, nil, nil)
        #expect(prefixBResults.count == 2, "Should find 2 keys with prefix B")

        for result in prefixBResults {
            #expect(result.key.starts(with: prefixB), "All results should have prefix B")
        }

        let startKey = Data31(prefixA + Data([0x02]) + Data(repeating: 0, count: 29))!
        let startKeyResults = try await stateBackend.getKeys(nil, startKey, nil)

        #expect(startKeyResults.count >= 4, "Should get at least 4 keys starting from specified key")

        for result in startKeyResults {
            let isSmaller = result.key.lexicographicallyPrecedes(startKey.data)
            #expect(!isSmaller, "All keys should be >= start key")
        }

        let prefixLimitedResults = try await stateBackend.getKeys(prefixA, nil, 2)
        #expect(prefixLimitedResults.count == 2, "Should respect both prefix and limit")

        for result in prefixLimitedResults {
            #expect(result.key.starts(with: prefixA), "All results should have prefix A")
        }
    }

    @Test
    func testGetKeysLargeBatch() async throws {
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())

        let keyCount = 1500
        var expectedKeys: Set<Data> = []

        for i in 0 ..< keyCount {
            var keyData = Data(repeating: 0, count: 31)
            keyData[0] = UInt8(i % 256)
            keyData[1] = UInt8(i / 256)

            let key = Data31(keyData)!
            let value = Data("value\(i)".utf8)

            try await stateBackend.writeRaw([(key: key, value: value)])
            expectedKeys.insert(key.data)
        }

        let results = try await stateBackend.getKeys(nil, nil, nil)
        let resultKeys = Set(results.map(\.key))

        #expect(results.count == keyCount, "Should return all \(keyCount) keys")
        #expect(resultKeys == expectedKeys, "Should return exactly the expected keys")
    }
}
