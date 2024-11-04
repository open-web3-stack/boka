import Codec
import Foundation
import Utils

public actor InMemoryBackend: StateBackend {
    private let config: ProtocolConfigRef
    private var store: [Data32: Data] = [:]

    public init(config: ProtocolConfigRef, store _: [Data32: Data] = [:]) {
        self.config = config
    }

    public func readImpl(_ key: any StateKey) async throws -> (Codable & Sendable)? {
        guard let value = store[key.encode()] else {
            return nil
        }
        return try JamDecoder.decode(key.decodeType(), from: value)
    }

    public func batchRead(_ keys: [any StateKey]) async throws -> [(key: any StateKey, value: Codable & Sendable)] {
        try keys.map {
            let data = try store[$0.encode()].unwrap()
            return try ($0, JamDecoder.decode($0.decodeType(), from: data))
        }
    }

    public func batchWrite(_ changes: [(key: any StateKey, value: Codable & Sendable)]) async throws {
        for (key, value) in changes {
            store[key.encode()] = try JamEncoder.encode(value)
        }
    }

    public func stateRoot() async throws -> Data32 {
        // TODO: store intermediate state so we can calculate the root efficiently
        try stateMerklize(kv: store)
    }
}
