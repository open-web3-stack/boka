import Foundation
import Utils

public enum StateBackendError: Error {
    case missingState
}

public protocol StateBackend: Sendable {
    func readImpl(_ key: any StateKey) async throws -> (Codable & Sendable)?

    func batchRead(_ keys: [any StateKey]) async throws -> [(key: any StateKey, value: Codable & Sendable)]
    mutating func batchWrite(_ changes: [(key: any StateKey, value: Codable & Sendable)]) async throws

    func readAll() async throws -> [Data32: Data]

    func stateRoot() async throws -> Data32

    // TODO: aux store for full key and intermidate merkle root
}

extension StateBackend {
    public func read<Key: StateKey>(_ key: Key) async throws -> Key.Value.ValueType {
        guard let ret = try await readImpl(key) as? Key.Value.ValueType else {
            throw StateBackendError.missingState
        }
        return ret
    }
}
