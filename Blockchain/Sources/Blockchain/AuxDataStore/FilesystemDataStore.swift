import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "FilesystemDataStore")

/// Filesystem-based storage for availability data shards
///
/// **Architecture Note:**
/// This is a low-level storage component that does NOT conform to `DataStoreProtocol`.
/// It is designed to be used internally by `ErasureCodingDataStore`, not directly.
///
/// Storage Architecture:
/// - `FilesystemDataStore` (this) → Low-level file storage (audit bundles + D³L shards)
/// - `RocksDBDataStore` → Metadata + indices (conforms to DataStoreProtocol)
/// - `ErasureCodingDataStore` → High-level facade combining both
///
/// Directory Structure:
/// ```
/// <data_path>/
/// ├── audit/                              # Short-term audit store
/// │   └── <erasure_root[:8]>/             # First 8 bytes for sharding
/// │       └── <erasure_root>.bin          # Full bundle data
/// └── d3l/                                # Long-term D³L store
///     └── <erasure_root[:4]>/             # First 4 bytes for sharding
///         └── <erasure_root>/
///             └── segments/
///                 └── <shard_index>.bin   # Individual shard data
/// ```
public actor FilesystemDataStore {
    private let dataPath: URL
    private let auditPath: URL
    private let d3lPath: URL
    private let fileManager: FileManager

    public init(dataPath: URL) async throws {
        self.dataPath = dataPath
        auditPath = dataPath.appendingPathComponent("audit")
        d3lPath = dataPath.appendingPathComponent("d3l")
        fileManager = FileManager.default

        // Create directories if they don't exist
        await createDirectoryIfNeeded(auditPath)
        await createDirectoryIfNeeded(d3lPath)

        logger.info("FilesystemDataStore initialized at \(dataPath.path)")
    }

    /// Store audit bundle (short-term storage)
    public func storeAuditBundle(erasureRoot: Data32, data: Data) async throws {
        let path = auditPathFor(erasureRoot: erasureRoot)
        try await writeDataAtomically(to: path, data: data)
        logger.debug("Stored audit bundle: erasureRoot=\(erasureRoot.toHexString()), size=\(data.count)")
    }

    /// Retrieve audit bundle
    public func getAuditBundle(erasureRoot: Data32) async throws -> Data? {
        let path = auditPathFor(erasureRoot: erasureRoot)
        guard fileManager.fileExists(atPath: path.path) else {
            return nil
        }
        return try await readData(from: path)
    }

    /// Delete audit bundle
    public func deleteAuditBundle(erasureRoot: Data32) async throws {
        let path = auditPathFor(erasureRoot: erasureRoot)
        try await removeFile(at: path)
        logger.trace("Deleted audit bundle: erasureRoot=\(erasureRoot.toHexString())")
    }

    /// Store D³L shard (long-term storage)
    public func storeD3LShard(erasureRoot: Data32, shardIndex: UInt16, data: Data) async throws {
        let path = d3lShardPathFor(erasureRoot: erasureRoot, shardIndex: shardIndex)
        try await writeDataAtomically(to: path, data: data)
        logger.trace("Stored D³L shard: erasureRoot=\(erasureRoot.toHexString()), index=\(shardIndex)")
    }

    /// Retrieve D³L shard
    public func getD3LShard(erasureRoot: Data32, shardIndex: UInt16) async throws -> Data? {
        let path = d3lShardPathFor(erasureRoot: erasureRoot, shardIndex: shardIndex)
        guard fileManager.fileExists(atPath: path.path) else {
            return nil
        }
        return try await readData(from: path)
    }

    /// Delete all D³L shards for an erasure root
    public func deleteD3LShards(erasureRoot: Data32) async throws {
        let shardsDir = d3lShardsDirectoryFor(erasureRoot: erasureRoot)
        try? await removeDirectory(at: shardsDir)
        logger.trace("Deleted D³L shards: erasureRoot=\(erasureRoot.toHexString())")
    }

    /// Get list of available shard indices for an erasure root
    public func getAvailableShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        let shardsDir = d3lShardsDirectoryFor(erasureRoot: erasureRoot)
        guard fileManager.fileExists(atPath: shardsDir.path) else {
            return []
        }

        let files = try fileManager.contentsOfDirectory(at: shardsDir, includingPropertiesForKeys: nil)
        var indices: [UInt16] = []

        for file in files {
            guard file.pathExtension == "bin" else { continue }
            if let index = UInt16(file.deletingPathExtension().lastPathComponent) {
                indices.append(index)
            }
        }

        return indices.sorted()
    }

    /// Get storage size for audit store
    public func getAuditStoreSize() async throws -> Int {
        try await getTotalSize(of: auditPath)
    }

    /// Get storage size for D³L store
    public func getD3LStoreSize() async throws -> Int {
        try await getTotalSize(of: d3lPath)
    }

    /// List all audit bundle erasure roots
    public func listAuditBundles() async throws -> [Data32] {
        var erasureRoots: [Data32] = []

        guard fileManager.fileExists(atPath: auditPath.path) else {
            return []
        }

        let prefixDirs = try fileManager.contentsOfDirectory(at: auditPath, includingPropertiesForKeys: nil)

        for prefixDir in prefixDirs {
            guard prefixDir.isDirectoryExists else { continue }

            let files = try fileManager.contentsOfDirectory(at: prefixDir, includingPropertiesForKeys: nil)

            for file in files {
                guard file.pathExtension == "bin" else { continue }
                let filename = file.deletingPathExtension().lastPathComponent
                if let erasureRoot = Data32(fromHexString: filename) {
                    erasureRoots.append(erasureRoot)
                }
            }
        }

        return erasureRoots.sorted()
    }

    /// List all D³L erasure roots
    public func listD3LEntries() async throws -> [Data32] {
        var erasureRoots: [Data32] = []

        guard fileManager.fileExists(atPath: d3lPath.path) else {
            return []
        }

        let prefixDirs = try fileManager.contentsOfDirectory(at: d3lPath, includingPropertiesForKeys: nil)

        for prefixDir in prefixDirs {
            guard prefixDir.isDirectoryExists else { continue }

            let erasureRootDirs = try fileManager.contentsOfDirectory(at: prefixDir, includingPropertiesForKeys: nil)

            for erasureRootDir in erasureRootDirs {
                guard erasureRootDir.isDirectoryExists else { continue }
                if let erasureRoot = Data32(fromHexString: erasureRootDir.lastPathComponent) {
                    erasureRoots.append(erasureRoot)
                }
            }
        }

        return erasureRoots.sorted()
    }
}

// MARK: - Helper Methods

extension FilesystemDataStore {
    /// Create directory if it doesn't exist
    private func createDirectoryIfNeeded(_ url: URL) async {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                logger.error("Path exists but is not a directory: \(url.path)")
                return
            }
        } else {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Write data atomically (write to temp file, then rename)
    private func writeDataAtomically(to url: URL, data: Data) async throws {
        // Ensure parent directory exists
        let parentDir = url.deletingLastPathComponent()
        await createDirectoryIfNeeded(parentDir)

        // Write to temporary file
        let tempUrl = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).tmp")

        // Create file and write data atomically
        try data.write(to: tempUrl)

        // Atomic rename
        try fileManager.moveItem(at: tempUrl, to: url)
    }

    /// Read data from file asynchronously (non-blocking)
    ///
    /// Uses Task.detached to run file I/O off the actor executor
    private func readData(from url: URL) async throws -> Data {
        try await Task.detached {
            try Data(contentsOf: url)
        }.value
    }

    /// Remove file
    private func removeFile(at url: URL) async throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Remove directory
    private func removeDirectory(at url: URL) async throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Calculate total size of directory
    private func getTotalSize(of url: URL) async throws -> Int {
        guard fileManager.fileExists(atPath: url.path) else {
            return 0
        }

        var totalSize = 0
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])

        while case let file as URL? = enumerator?.nextObject() {
            let resourceValues = try file?.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = resourceValues?.fileSize {
                totalSize += fileSize
            }
        }

        return totalSize
    }

    /// Path for audit bundle storage
    private func auditPathFor(erasureRoot: Data32) -> URL {
        let prefix = erasureRoot.data.prefix(8).toHexString()
        let prefixDir = auditPath.appendingPathComponent(prefix)
        let filename = erasureRoot.toHexString() + ".bin"
        return prefixDir.appendingPathComponent(filename)
    }

    /// Path for D³L shard storage
    private func d3lShardPathFor(erasureRoot: Data32, shardIndex: UInt16) -> URL {
        let shardsDir = d3lShardsDirectoryFor(erasureRoot: erasureRoot)
        let filename = "\(shardIndex).bin"
        return shardsDir.appendingPathComponent(filename)
    }

    /// Directory containing D³L shards for an erasure root
    private func d3lShardsDirectoryFor(erasureRoot: Data32) -> URL {
        let prefix = erasureRoot.data.prefix(4).toHexString()
        let prefixDir = d3lPath.appendingPathComponent(prefix)
        let erasureRootDir = prefixDir.appendingPathComponent(erasureRoot.toHexString())
        return erasureRootDir.appendingPathComponent("segments")
    }
}

// MARK: - Errors

public enum FilesystemDataStoreError: Error {
    case pathNotDirectory(path: URL)
    case directoryNotFound(path: URL)
    case fileNotFound(path: URL)
    case diskFull
    case permissionDenied(path: URL)
    case corruptedData(erasureRoot: Data32)
    case invalidSegmentLength(expected: Int, actual: Int)
}

// MARK: - URL Extension

extension URL {
    fileprivate var isDirectoryExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
