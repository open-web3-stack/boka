import Foundation
import Testing
import Utils

@testable import Blockchain

private func merklize(_ data: some Sequence<(key: Data31, value: Data)>) -> Data32 {
    var dict: [Data31: Data] = [:]
    for (key, value) in data {
        dict[key] = value
    }
    return try! stateMerklize(kv: dict)
}

struct StateTrieTests {
    let backend = InMemoryBackend()

    // MARK: - Basic Operations Tests

    @Test
    func testEmptyTrie() async throws {
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let key = Data31.random()
        let value = try await trie.read(key: key)
        #expect(value == nil)
    }

    @Test
    func testInsertAndRetrieveSingleValue() async throws {
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let key = Data31(Data([1]).blake2b256hash().data[relative: 0 ..< 31])!
        let value = Data("test value".utf8)

        try await trie.update([(key: key, value: value)])
        try await trie.save()

        let retrieved = try await trie.read(key: key)
        #expect(retrieved == value)
    }

    @Test
    func testInsertAndRetrieveSimple() async throws {
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let remainKey = Data(repeating: 0, count: 30)
        let pairs = [
            (key: Data31(Data([0b0000_0000]) + remainKey)!, value: Data([0])),
            (key: Data31(Data([0b1000_0000]) + remainKey)!, value: Data([1])),
            (key: Data31(Data([0b0100_0000]) + remainKey)!, value: Data([2])),
            (key: Data31(Data([0b1100_0000]) + remainKey)!, value: Data([3])),
        ]

        for (i, pair) in pairs.enumerated() {
            try await trie.update([(key: pair.key, value: pair.value)])

            let expectedRoot = merklize(pairs[0 ... i])
            let trieRoot = await trie.rootHash
            #expect(expectedRoot == trieRoot)
        }

        for (i, (key, value)) in pairs.enumerated() {
            let retrieved = try await trie.read(key: key)
            #expect(retrieved == value, "Failed at index \(i)")
        }

        try await trie.save()

        for (i, (key, value)) in pairs.enumerated() {
            let retrieved = try await trie.read(key: key)
            #expect(retrieved == value, "Failed at index \(i)")
        }
    }

    @Test
    func testInsertAndRetrieveMultipleValues() async throws {
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let pairs = (0 ..< 50).map { i in
            let data = Data([UInt8(i)])
            return (key: Data31(data.blake2b256hash().data[relative: 0 ..< 31])!, value: data)
        }

        for (i, pair) in pairs.enumerated() {
            try await trie.update([(key: pair.key, value: pair.value)])

            let expectedRoot = merklize(pairs[0 ... i])
            let trieRoot = await trie.rootHash
            #expect(expectedRoot == trieRoot)
        }

        for (i, (key, value)) in pairs.enumerated() {
            let retrieved = try await trie.read(key: key)
            #expect(retrieved == value, "Failed at index \(i)")
        }

        try await trie.save()

        for (i, (key, value)) in pairs.enumerated() {
            let retrieved = try await trie.read(key: key)
            #expect(retrieved == value, "Failed at index \(i)")
        }
    }

    // MARK: - Update Tests

    @Test
    func testUpdateExistingValue() async throws {
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let key = Data31.random()
        let value1 = Data("value1".utf8)
        let value2 = Data("value2".utf8)

        try await trie.update([(key: key, value: value1)])
        try await trie.save()

        try await trie.update([(key: key, value: value2)])
        try await trie.save()

        let retrieved = try await trie.read(key: key)
        #expect(retrieved == value2)
    }

    @Test
    func testDeleteValue() async throws {
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let key = Data31.random()
        let value = Data("test".utf8)

        try await trie.update([(key: key, value: value)])
        try await trie.save()

        try await trie.update([(key: key, value: nil)])
        try await trie.save()

        let retrieved = try await trie.read(key: key)
        #expect(retrieved == nil)
    }

    // MARK: - Large Value Tests

    @Test
    func testLargeValue() async throws {
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let key = Data31.random()
        let value = Data(repeating: 0xFF, count: 1000) // Value larger than 32 bytes

        try await trie.update([(key: key, value: value)])
        try await trie.save()

        let retrieved = try await trie.read(key: key)
        #expect(retrieved == value)
    }

    // MARK: - Root Hash Tests

    @Test
    func testRootHashChanges() async throws {
        let trie = StateTrie(rootHash: Data32(), backend: backend)
        let initialRoot = await trie.rootHash

        let key = Data31.random()
        let value = Data("test".utf8)

        try await trie.update([(key: key, value: value)])
        try await trie.save()

        let newRoot = await trie.rootHash
        #expect(initialRoot != newRoot)
    }

    @Test
    func testRootHashConsistency() async throws {
        let trie1 = StateTrie(rootHash: Data32(), backend: backend)
        let trie2 = StateTrie(rootHash: Data32(), backend: backend)

        let pairs = (0 ..< 5).map { i in
            let data = Data(String(i).utf8)
            return (key: Data31(data.blake2b256hash().data[relative: 0 ..< 31])!, value: data)
        }

        // Apply same updates to both tries
        try await trie1.update(pairs)
        try await trie1.save()

        try await trie2.update(pairs)
        try await trie2.save()

        #expect(await trie1.rootHash == trie2.rootHash)
    }

    // MARK: - Critical Bug Tests

    @Test
    func testRestructWithSimilarPrefixes() async throws {
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())

        // Step 1: Add the specific key that shouldn't disappear
        let problematicKey = Data31(Data(fromHexString: "00ff00ff00ff00ff69d6f38a4dda314f8193a3d5e9f41f68a3ec49f5a521b8")!)!
        let problematicValue = Data(fromHexString: "5251fc63d6ad1a0cd5d52734c02ba70f317dfcb2d63614c12835d07aa8f15f40")!

        try await stateBackend.writeRaw([(key: problematicKey, value: problematicValue)])

        // Verify it exists
        let beforeValue = try await stateBackend.readRaw(problematicKey)
        #expect(beforeValue == problematicValue, "Problematic key should exist initially")

        // Step 2: Simulate the exact pattern - create similar prefix keys and delete some
        let similarPrefixUpdates: [(Data31, Data?)] = [
            // Keys being deleted (similar to bug scenario)
            (Data31(Data(fromHexString: "00ff00ff00ff00ff92dbdebb04092bf7679ea5a173d9ce6ab6d487575dcd64")!)!, nil),
            (Data31(Data(fromHexString: "00ff00ff00ff00ff0d4bbb181695eda4ae707a081a2c564515af1e5d15d9a5")!)!, nil),
            (Data31(Data(fromHexString: "00ff00ff00ff00ffeadc80c9230c15c9583b31843f94de3a6ad199cc8005cc")!)!, nil),
            (Data31(Data(fromHexString: "00ff00ff00ff00ff2c8ea9585fd170a4be7405a0967ee61ad25e5c6fab55a9")!)!, nil),
            (Data31(Data(fromHexString: "00ff00ff00ff00ff43bacaf626cdcadd9d1c73dbfe3a9b1ede2b7ea752d042")!)!, nil),
        ]

        // Perform the deletions
        try await stateBackend.writeRaw(similarPrefixUpdates)

        // Step 3: The critical test - does the problematic key still exist?
        let afterValue = try await stateBackend.readRaw(problematicKey)
        #expect(afterValue == problematicValue, "Problematic key should still exist after similar prefix operations")

        // Also verify the operations themselves worked correctly
        for (key, expectedValue) in similarPrefixUpdates {
            let actualValue = try await stateBackend.readRaw(key)
            #expect(actualValue == expectedValue, "Key \(key.toHexString()) should have expected value after update")
        }
    }

    @Test
    func testMixedCoreAndServiceKeys() async throws {
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())

        // Step 1: Add the problematic key first
        let problematicKey = Data31(Data(fromHexString: "00ff00ff00ff00ff69d6f38a4dda314f8193a3d5e9f41f68a3ec49f5a521b8")!)!
        let problematicValue = Data(fromHexString: "5251fc63d6ad1a0cd5d52734c02ba70f317dfcb2d63614c12835d07aa8f15f40")!

        try await stateBackend.writeRaw([(key: problematicKey, value: problematicValue)])

        // Verify it was actually written
        let verifyValue = try await stateBackend.readRaw(problematicKey)
        #expect(verifyValue == problematicValue, "Problematic key should be written correctly")

        // Step 2: Simulate the exact mixed update pattern
        let mixedUpdates: [(Data31, Data?)] = [
            // Core state keys
            (Data31(Data(fromHexString: "0a000000000000000000000000000000000000000000000000000000000000")!)!, Data([0x01, 0x02])),
            (
                Data31(Data(fromHexString: "0b000000000000000000000000000000000000000000000000000000000000")!)!,
                Data([0x01, 0x02, 0x03, 0x04])
            ),
            (
                Data31(Data(fromHexString: "0e000000000000000000000000000000000000000000000000000000000000")!)!,
                Data(repeating: 0xFF, count: 12)
            ),
            (
                Data31(Data(fromHexString: "03000000000000000000000000000000000000000000000000000000000000")!)!,
                Data(repeating: 0xAA, count: 1729)
            ),

            // Service account deletions
            (Data31(Data(fromHexString: "00ff00ff00ff00ff92dbdebb04092bf7679ea5a173d9ce6ab6d487575dcd64")!)!, nil),
            (Data31(Data(fromHexString: "00ff00ff00ff00ff0d4bbb181695eda4ae707a081a2c564515af1e5d15d9a5")!)!, nil),

            // More core keys
            (
                Data31(Data(fromHexString: "07000000000000000000000000000000000000000000000000000000000000")!)!,
                Data(repeating: 0xBB, count: 2016)
            ),
            (
                Data31(Data(fromHexString: "04000000000000000000000000000000000000000000000000000000000000")!)!,
                Data(repeating: 0xCC, count: 2546)
            ),
        ]

        // Write keys one by one to debug
        for (i, (key, value)) in mixedUpdates.enumerated() {
            try await stateBackend.writeRaw([(key: key, value: value)])

            // Check if previous keys still exist
            if i > 0 {
                for j in 0 ..< i {
                    let (prevKey, prevExpectedValue) = mixedUpdates[j]
                    let prevActualValue = try await stateBackend.readRaw(prevKey)
                    if prevExpectedValue != prevActualValue {
                        Issue.record("CORRUPTION DETECTED at operation \(i)! Previous key \(j) changed!")
                    }
                }
            }
        }

        // Step 3: The critical test - does the problematic key still exist?
        let afterValue = try await stateBackend.readRaw(problematicKey)
        #expect(afterValue == problematicValue, "Problematic key should survive mixed core state and service account operations")

        // Verify all mixed operations worked correctly
        for (key, expectedValue) in mixedUpdates {
            let actualValue = try await stateBackend.readRaw(key)
            #expect(actualValue == expectedValue, "Mixed update key \(key.toHexString()) should have expected value")
        }
    }

    // TODO: test for gc, ref counting & pruning, raw value ref counting & cleaning
}
