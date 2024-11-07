import Foundation
import Utils

public enum StateTrieBackendOperation: Sendable {
    case write(key: Data, value: Data)
    case refIncrement(key: Data)
    case refDecrement(key: Data)
}

// key: trie node hash (32 bytes)
// value: trie node data (64 bytes)
public protocol StateTrieBackend: Sendable {
    func read(key: Data) async throws -> Data?
    func readAll(prefix: Data, startKey: Data?, limit: UInt32?) async throws -> [(key: Data, value: Data)]
    func batchRead(keys: [Data]) async throws -> [(key: Data, value: Data?)]
    func batchUpdate(_ ops: [StateTrieBackendOperation]) async throws

    // remove entries with zero ref count
    func gc() async throws
}
