import Codec
import Foundation
import Utils

public enum StateBackendError: Error {
    case missingState(key: Sendable)
    case invalidData
}

public final class StateBackend: Sendable {
    private let impl: StateBackendProtocol
    private let config: ProtocolConfigRef
    private let trie: StateTrie

    public init(_ impl: StateBackendProtocol, config: ProtocolConfigRef, rootHash: Data32) {
        self.impl = impl
        self.config = config
        trie = StateTrie(rootHash: rootHash, backend: impl)
    }

    public var rootHash: Data32 {
        get async {
            await trie.rootHash
        }
    }

    public func read<Key: StateKey>(_ key: Key) async throws -> Key.Value? {
        let encodedKey = key.encode()
        if let ret = try await trie.read(key: encodedKey) {
            guard let ret = try JamDecoder.decode(key.decodeType(), from: ret, withConfig: config) as? Key.Value else {
                throw StateBackendError.invalidData
            }
            return ret
        }
        if Key.optional {
            return nil
        }
        throw StateBackendError.missingState(key: key)
    }

    public func getKeys(_ prefix: Data?, _ startKey: Data31?, _ limit: UInt32?) async throws -> [(key: Data, value: Data)] {
        let prefixData = prefix ?? Data()
        let startKeyData = startKey?.data

        var stateKeyValues: [(key: Data, value: Data)] = []
        var currentStartKey: Data? = nil
        let batchSize: UInt32 = 1000

        while true {
            let batch = try await impl.readAll(prefix: Data(), startKey: currentStartKey, limit: batchSize)

            if batch.isEmpty {
                break
            }

            var lastProcessedKey: Data?

            for (nodeKey, trieNodeData) in batch {
                if let limit, stateKeyValues.count >= Int(limit) {
                    return stateKeyValues
                }

                guard trieNodeData.count == 64 else {
                    lastProcessedKey = nodeKey
                    continue
                }

                let firstByte = trieNodeData[relative: 0]
                let isLeaf = (firstByte & 0b1100_0000) == 0b1000_0000 || (firstByte & 0b1100_0000) == 0b1100_0000

                if isLeaf {
                    let stateKey = Data(trieNodeData[relative: 1 ..< 32])

                    if !prefixData.isEmpty, !stateKey.starts(with: prefixData) {
                        lastProcessedKey = nodeKey
                        continue
                    }

                    if let startKeyData, stateKey.lexicographicallyPrecedes(startKeyData) {
                        lastProcessedKey = nodeKey
                        continue
                    }

                    if let value = try await trie.read(key: Data31(stateKey)!) {
                        stateKeyValues.append((key: stateKey, value: value))
                    }
                }

                lastProcessedKey = nodeKey
            }

            if batch.count < Int(batchSize) {
                break
            }

            if let lastKey = lastProcessedKey {
                // Increment key for next batch
                // TODO: maybe add a nextKey method to impl
                var result = lastKey
                var shouldContinue = false
                for i in (0 ..< result.count).reversed() {
                    if result[i] < 255 {
                        result[i] += 1
                        shouldContinue = true
                        break
                    }
                    result[i] = 0
                }
                currentStartKey = shouldContinue ? result : nil
                if !shouldContinue {
                    break
                }
            } else {
                break
            }
        }

        if let limit, stateKeyValues.count > Int(limit) {
            stateKeyValues = Array(stateKeyValues.prefix(Int(limit)))
        }

        return stateKeyValues
    }

    public func batchRead(_ keys: [any StateKey]) async throws -> [(key: any StateKey, value: (Codable & Sendable)?)] {
        var ret = [(key: any StateKey, value: (Codable & Sendable)?)]()
        ret.reserveCapacity(keys.count)
        for key in keys {
            try await ret.append((key, read(key)))
        }
        return ret
    }

    public func write(_ values: any Sequence<(key: Data31, value: (Codable & Sendable)?)>) async throws {
        try await trie.update(values.map { try (key: $0.key, value: $0.value.map { try JamEncoder.encode($0) }) })
        try await trie.save()
    }

    public func readRaw(_ key: Data31) async throws -> Data? {
        try await trie.read(key: key)
    }

    public func writeRaw(_ values: [(key: Data31, value: Data?)]) async throws {
        try await trie.update(values)
        try await trie.save()
    }

    public func gc() async throws {
        try await impl.gc { data in
            guard data.count == 64 else {
                // unexpected data size
                return nil
            }
            let isRegularLeaf = data[0] & 0b1100_0000 == 0b1100_0000
            if isRegularLeaf {
                return Data32(data.suffix(from: 32))!
            }
            return nil
        }
    }

    public func debugPrint() async throws {
        try await trie.debugPrint()
    }
}
