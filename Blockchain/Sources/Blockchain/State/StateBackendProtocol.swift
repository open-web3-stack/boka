import Foundation
import Utils

public enum StateBackendOperation: Sendable {
    case write(key: Data, value: Data)
    case writeRawValue(key: Data32, value: Data)
    case refIncrement(key: Data)
    case refDecrement(key: Data)
}

/// key: trie node hash (32 bytes)
/// value: trie node data (64 bytes)
/// ref counting requirements:
///   - write do not increment ref count, only explicit ref increment do
///   - lazy prune is used. e.g. when ref count is reduced to zero, the value will only be removed
///     when gc is performed
///   - raw value have its own ref counting
///   - writeRawValue increment ref count, and write if necessary
///   - raw value ref count is only decremented when connected trie node is removed during gc
public protocol StateBackendProtocol: Sendable {
    func read(key: Data) async throws -> Data?
    func readAll(prefix: Data, startKey: Data?, limit: UInt32?) async throws -> [(key: Data, value: Data)]
    func batchUpdate(_ ops: [StateBackendOperation]) async throws

    // hash is the blake2b256 hash of the value
    func readValue(hash: Data32) async throws -> Data?

    /// remove entries with zero ref count
    /// callback returns a dependent raw value key if the data is regular leaf node
    func gc(callback: @Sendable (Data) -> Data32?) async throws
}
