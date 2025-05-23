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

    // TODO: test for gc, ref counting & pruning, raw value ref counting & cleaning
}
