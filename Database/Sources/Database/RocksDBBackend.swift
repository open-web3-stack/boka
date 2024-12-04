import Blockchain
import Foundation
import Utils

public final class RocksDBBackend: StateBackendProtocol {
    public init() {}

    public func read(key _: Data) async throws -> Data? {
        fatalError("unimplemented")
    }

    public func readAll(prefix _: Data, startKey _: Data?, limit _: UInt32?) async throws -> [(key: Data, value: Data)] {
        fatalError("unimplemented")
    }

    public func batchUpdate(_: [StateBackendOperation]) async throws {
        fatalError("unimplemented")
    }

    public func readValue(hash _: Data32) async throws -> Data? {
        fatalError("unimplemented")
    }

    public func gc(callback _: @Sendable (Data) -> Data32?) async throws {
        fatalError("unimplemented")
    }
}
