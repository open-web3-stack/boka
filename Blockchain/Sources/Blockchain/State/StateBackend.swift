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

    /// Get keys with optional prefix, startKey, and limit using trie traversal
    /// - Parameters:
    ///   - prefix: Optional prefix to filter keys. If provided, uses O(prefix_bits + K) trie traversal. If nil, scans all keys O(N).
    ///   - startKey: Optional starting key for pagination. Returns keys >= startKey in lexicographic order.
    ///   - limit: Optional maximum number of results to return.
    /// - Returns: Array of (key, value) pairs in lexicographic order (guaranteed by trie structure)
    public func getKeys(_ prefix: Data?, _ startKey: Data31?, _ limit: UInt32?) async throws -> [(key: Data, value: Data)] {
        // Step 1: Collect all matching keys with values using efficient trie traversal
        // Note: Trie traversal visits left (0) before right (1), so results are already sorted
        var keyValues: [(key: Data31, value: Data)]

        if let prefix, !prefix.isEmpty {
            let bitsCount = UInt8(prefix.count * 8)
            keyValues = try await trie.getKeyValues(matchingPrefix: prefix, bitsCount: bitsCount)
        } else {
            keyValues = try await trie.getKeyValues(matchingPrefix: Data(), bitsCount: 0)
        }

        // Step 2: Apply startKey filter
        if let startKey {
            keyValues = keyValues.filter { !$0.key.data.lexicographicallyPrecedes(startKey.data) }
        }

        // Step 3: Apply limit
        if let limit {
            keyValues = Array(keyValues.prefix(Int(limit)))
        }

        // Step 4: Convert to (Data, Data) format
        return keyValues.map { (key: $0.key.data, value: $0.value) }
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
        let updates: [(key: Data31, value: Data?)] = try values.map { try (key: $0.key, value: $0.value.map { try JamEncoder.encode($0) }) }

        try await trie.update(updates)
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
            guard data.count == 65 else {
                // unexpected data size
                return nil
            }
            let isRegularLeaf = data[0] == 2 // type byte for regularLeaf
            if isRegularLeaf {
                return Data32(data.suffix(from: 33))! // right child starts at byte 33
            }
            return nil
        }
    }

    public func debugPrint() async throws {
        try await trie.debugPrint()
    }
}
