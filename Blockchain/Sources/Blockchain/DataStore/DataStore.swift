import Foundation

public protocol DataStoreProtocol: Sendable {
    func read(path: URL) async throws -> Data?
    func write(path: URL, value: Data) async throws
    func delete(path: URL) async throws
}

public final class DataStore: Sendable {
    private let impl: DataStoreProtocol
    private let basePath: URL

    public init(_ impl: DataStoreProtocol, basePath: URL) {
        self.impl = impl
        self.basePath = basePath
    }

    // partitioning files so that we won't have too many files in a single directory
    private func getPath(path: String, name: String) -> URL {
        var ret = basePath
        ret.append(component: path)
        var name = name[...]
        if let first = name.first {
            ret.append(component: String(first), directoryHint: .isDirectory)
            name = name.dropFirst()
        }
        if let second = name.first {
            ret.append(component: String(second), directoryHint: .isDirectory)
            name = name.dropFirst()
        }
        ret.append(component: String(name), directoryHint: .notDirectory)
        return ret
    }

    public func read(path: String, name: String) async throws -> Data? {
        try await impl.read(path: getPath(path: path, name: name))
    }

    public func write(path: String, name: String, value: Data) async throws {
        try await impl.write(path: getPath(path: path, name: name), value: value)
    }

    public func delete(path: String, name: String) async throws {
        try await impl.delete(path: getPath(path: path, name: name))
    }
}
