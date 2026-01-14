import Foundation
import Utils

public enum StateBackendOperation: Sendable {
    case write(key: Data, value: Data)
    case writeRawValue(key: Data32, value: Data)
    case refUpdate(key: Data, delta: Int64) // Apply delta to reference count (can be positive or negative)
}

public protocol StateBackendIterator: Sendable {
    func next() async throws -> (key: Data, value: Data)?
}

/// key: trie node hash (31 bytes)
/// value: trie node data (65 bytes - includes node type + original child data)
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
    func createIterator(prefix: Data, startKey: Data?) async throws -> StateBackendIterator
    func batchUpdate(_ ops: [StateBackendOperation]) async throws

    // hash is the blake2b256 hash of the value
    func readValue(hash: Data32) async throws -> Data?

    /// Read multiple nodes in a single batch operation
    /// - Parameter keys: List of node keys to read (31 bytes each)
    /// - Returns: Dictionary mapping keys to their node data (65 bytes each)
    /// - Note: Missing keys are omitted from result (not an error)
    func batchRead(keys: [Data]) async throws -> [Data: Data]

    /// remove entries with zero ref count
    /// callback returns a dependent raw value key if the data is regular leaf node
    func gc(callback: @Sendable (Data) -> Data32?) async throws
}

/// Default implementation of batchRead using sequential reads
extension StateBackendProtocol {
    public func batchRead(keys: [Data]) async throws -> [Data: Data] {
        var result: [Data: Data] = [:]
        // Fallback: sequential reads for backends that don't implement batch loading
        for key in keys {
            if let data = try await read(key: key) {
                result[key] = data
            }
        }
        return result
    }
}
