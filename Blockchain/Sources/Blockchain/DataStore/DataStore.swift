import Foundation

public protocol DataStoreProtocol: Sendable {
    func read(path: URL) async throws -> Data?
    func write(path: URL, value: Data) async throws
    func delete(path: URL) async throws
}

public final class DataStore: Sendable {
    private let impl: DataStoreProtocol
    private let basePath: URL

    public init(impl: DataStoreProtocol, basePath: URL) {
        self.impl = impl
        self.basePath = basePath
    }

    // partitioning files so that we won't have too many files in a single directory
    private func path(for name: String) -> URL {
        var path = basePath
        var name = name[...]
        if let first = name.first {
            path = path.appendingPathComponent(String(first), isDirectory: true)
            name = name.dropFirst()
        }
        if let second = name.first {
            path = path.appendingPathComponent(String(second), isDirectory: true)
            name = name.dropFirst()
        }
        return path.appendingPathComponent(String(name), isDirectory: false)
    }

    public func read(name: String) async throws -> Data? {
        try await impl.read(path: path(for: name))
    }

    public func write(name: String, value: Data) async throws {
        try await impl.write(path: path(for: name), value: value)
    }

    public func delete(name: String) async throws {
        try await impl.delete(path: path(for: name))
    }
}
