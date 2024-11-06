import Foundation
import Utils

public enum StateBackendOperation: Sendable {
    case write(key: Data, value: Data)
    case refIncrement(key: Data)
    case refDecrement(key: Data)
}

public protocol StateBackendProtocol: Sendable {
    func read(key: Data) async throws -> Data?
    func readAll(prefix: Data, startKey: Data?, limit: UInt32?) async throws -> [(key: Data, value: Data)]
    func batchRead(keys: [Data]) async throws -> [(key: Data, value: Data?)]
    func batchUpdate(_ ops: [StateBackendOperation]) async throws

    // remove entries with zero ref count
    func gc() async throws
}
