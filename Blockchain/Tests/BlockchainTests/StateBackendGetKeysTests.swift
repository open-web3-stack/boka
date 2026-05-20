@testable import Blockchain
import Foundation
import Testing
import Utils

private func stateKey(_ first: UInt8, _ second: UInt8 = 0) -> Data31 {
    var data = Data(repeating: 0, count: 31)
    data[0] = first
    data[1] = second
    return Data31(data)!
}

struct StateBackendGetKeysTests {
    @Test("getKeys applies startKey and limit during trie traversal")
    func getKeysStartKeyAndLimit() async throws {
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let keys = (0 ..< 6).map { stateKey(0, UInt8($0)) }

        try await stateBackend.writeRaw(keys.map { (key: $0, value: Data([$0.data[1]])) })

        let results = try await stateBackend.getKeys(Data([0]), stateKey(0, 2), 3)

        #expect(results.map(\.key) == keys[2 ..< 5].map(\.data))
        #expect(results.map(\.value) == [Data([2]), Data([3]), Data([4])])
    }

    @Test("getKeys returns no results when prefix is before startKey")
    func getKeysPrefixBeforeStartKey() async throws {
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let keys = (0 ..< 4).map { stateKey(0, UInt8($0)) }

        try await stateBackend.writeRaw(keys.map { (key: $0, value: Data([$0.data[1]])) })

        let results = try await stateBackend.getKeys(Data([0]), stateKey(1), 10)

        #expect(results.isEmpty)
    }

    @Test("getKeys keeps prefix results when prefix is after startKey")
    func getKeysPrefixAfterStartKey() async throws {
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let keys = [
            stateKey(0, 0),
            stateKey(2, 0),
            stateKey(2, 1),
        ]

        try await stateBackend.writeRaw(keys.map { (key: $0, value: Data([$0.data[0], $0.data[1]])) })

        let results = try await stateBackend.getKeys(Data([2]), stateKey(1), nil)

        #expect(results.map(\.key) == keys[1...].map(\.data))
    }

    @Test("getKeys treats UInt32.max limit as an unbounded page")
    func getKeysMaxLimit() async throws {
        let backend = InMemoryBackend()
        let stateBackend = StateBackend(backend, config: ProtocolConfigRef.dev, rootHash: Data32())
        let keys = [
            stateKey(0, 0),
            stateKey(0, 1),
            stateKey(0, 2),
        ]

        try await stateBackend.writeRaw(keys.map { (key: $0, value: Data([$0.data[1]])) })

        let results = try await stateBackend.getKeys(Data([0]), nil, UInt32.max)

        #expect(results.map(\.key) == keys.map(\.data))
        #expect(results.map(\.value) == [Data([0]), Data([1]), Data([2])])
    }
}
