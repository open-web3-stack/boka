import Foundation

public actor FilesystemDataStore: DataStoreProtocol {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func read(path: URL) async throws -> Data? {
        try Data(contentsOf: path)
    }

    public func write(path: URL, value: Data) async throws {
        let base = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        try value.write(to: path)
    }

    public func delete(path: URL) async throws {
        try fileManager.removeItem(at: path)
    }
}
