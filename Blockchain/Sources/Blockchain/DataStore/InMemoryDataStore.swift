import Foundation

public actor InMemoryDataStore: DataStoreProtocol {
    private var store: [URL: Data] = [:]

    public func read(name: URL) async throws -> Data? {
        store[name]
    }

    public func write(name: URL, value: Data) async throws {
        store[name] = value
    }

    public func delete(name: URL) async throws {
        store[name] = nil
    }
}
