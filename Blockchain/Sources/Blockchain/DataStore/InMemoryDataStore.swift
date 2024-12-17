import Foundation

public actor InMemoryDataStore: DataStoreProtocol {
    private var store: [URL: Data] = [:]

    public init() {}

    public func read(path: URL) async throws -> Data? {
        store[path]
    }

    public func write(path: URL, value: Data) async throws {
        store[path] = value
    }

    public func delete(path: URL) async throws {
        store[path] = nil
    }
}
