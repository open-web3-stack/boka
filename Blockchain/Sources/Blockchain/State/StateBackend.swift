import Codec
import Foundation
import Utils

public enum StateBackendError: Error {
    case missingState
    case invalidData
}

public final class StateBackend: Sendable {
    private let impl: StateBackendProtocol
    private let config: ProtocolConfigRef
    public let rootHash: Data32

    public init(_ impl: StateBackendProtocol, config: ProtocolConfigRef, rootHash: Data32) {
        self.impl = impl
        self.config = config
        self.rootHash = rootHash
    }

    public func read<Key: StateKey>(_ key: Key) async throws -> Key.Value {
        let encodedKey = key.encode().data
        if let ret = try await impl.read(key: encodedKey) {
            guard let ret = try JamDecoder.decode(key.decodeType(), from: ret, withConfig: config) as? Key.Value else {
                throw StateBackendError.invalidData
            }
            return ret
        }
        if Key.optional {
            return Key.Value?.none as! Key.Value
        }
        throw StateBackendError.missingState
    }

    public func batchRead(_ keys: [any StateKey]) async throws -> [(key: any StateKey, value: (Codable & Sendable)?)] {
        let encodedKeys = keys.map { $0.encode().data }
        let result = try await impl.batchRead(keys: encodedKeys)
        return try zip(result, keys).map { data, key in
            guard let rawValue = data.value else {
                return (key: key, value: nil)
            }
            let value = try JamDecoder.decode(key.decodeType(), from: rawValue, withConfig: config)
            return (key: key, value: value)
        }
    }

    public func readAll() async throws -> [Data32: Data] {
        let all = try await impl.readAll(prefix: Data(), startKey: nil, limit: nil)
        var result = [Data32: Data]()
        for (key, value) in all {
            try result[Data32(key).unwrap()] = value
        }
        return result
    }

    public func newBackend(rootHash: Data32) -> StateBackend {
        StateBackend(impl: impl, config: config, rootHash: rootHash)
    }
}

// MARK: - TrieNode

extension StateBackend {
    public func readTrieNode(_ key: Data) async throws -> Data? {
        try await impl.read(key: key)
    }

    public func batchUpdateTrieNodes(_ ops: [StateBackendOperation]) async throws {
        try await impl.batchUpdate(ops)
    }

    public func gc() async throws {
        try await impl.gc()
    }
}
