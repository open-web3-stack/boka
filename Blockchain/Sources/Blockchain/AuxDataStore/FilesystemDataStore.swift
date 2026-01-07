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

    /// Synchronous init to avoid actor contention when multiple tests create instances concurrently
    public init(dataPath: URL) throws {
        self.dataPath = dataPath
        auditPath = dataPath.appendingPathComponent("audit")
        d3lPath = dataPath.appendingPathComponent("d3l")
        fileManager = FileManager.default

        // Create directories synchronously
        try createDirectoryIfNeededSync(auditPath)
        try createDirectoryIfNeededSync(d3lPath)

        // logger.info("FilesystemDataStore initialized at \(dataPath.path)")
    }

    /// Synchronous version for use in init to avoid actor contention
    private nonisolated func createDirectoryIfNeededSync(_ url: URL) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if exists {
            guard isDirectory.boolValue else {
                throw FilesystemDataStoreError.directoryCreationFailed("Path exists but is not a directory: \(url.path)")
            }
        } else {
            do {
                try fm.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                // Verify if it was created by another task
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    return
                }
                throw FilesystemDataStoreError
                    .directoryCreationFailed("Failed to create directory at \(url.path): \(error.localizedDescription)")
            }
        }
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
    ///
    /// Uses Task.detached to run blocking file I/O off the actor executor.
    public func getAvailableShardIndices(erasureRoot: Data32) async throws -> [UInt16] {
        // Compute path before entering Task.detached to avoid concurrency issues
        let shardsDirPath = d3lShardsDirectoryFor(erasureRoot: erasureRoot).path

        return try await Task.detached {
            guard FileManager.default.fileExists(atPath: shardsDirPath) else {
                return []
            }

            let files = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: shardsDirPath),
                includingPropertiesForKeys: nil
            )
            var indices: [UInt16] = []
            indices.reserveCapacity(files.count)

            for file in files {
                guard file.pathExtension == "bin" else { continue }
                if let index = UInt16(file.deletingPathExtension().lastPathComponent) {
                    indices.append(index)
                }
            }

            return indices.sorted()
        }.value
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
    ///
    /// Uses Task.detached to run blocking file I/O off the actor executor.
    public func listAuditBundles() async throws -> [Data32] {
        let auditPathString = auditPath.path

        return try await Task.detached {
            var erasureRoots: [Data32] = []

            guard FileManager.default.fileExists(atPath: auditPathString) else {
                return []
            }

            let prefixDirs = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: auditPathString),
                includingPropertiesForKeys: nil
            )

            for prefixDir in prefixDirs {
                guard prefixDir.isDirectoryExists else { continue }

                let files = try FileManager.default.contentsOfDirectory(at: prefixDir, includingPropertiesForKeys: nil)

                for file in files {
                    guard file.pathExtension == "bin" else { continue }
                    let filename = file.deletingPathExtension().lastPathComponent
                    if let erasureRoot = Data32(fromHexString: filename) {
                        erasureRoots.append(erasureRoot)
                    }
                }
            }

            return erasureRoots.sorted()
        }.value
    }

    /// List all D³L erasure roots
    ///
    /// Uses Task.detached to run blocking file I/O off the actor executor.
    public func listD3LEntries() async throws -> [Data32] {
        let d3lPathString = d3lPath.path

        return try await Task.detached {
            var erasureRoots: [Data32] = []

            guard FileManager.default.fileExists(atPath: d3lPathString) else {
                return []
            }

            let prefixDirs = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: d3lPathString),
                includingPropertiesForKeys: nil
            )

            for prefixDir in prefixDirs {
                guard prefixDir.isDirectoryExists else { continue }

                let erasureRootDirs = try FileManager.default.contentsOfDirectory(at: prefixDir, includingPropertiesForKeys: nil)

                for erasureRootDir in erasureRootDirs {
                    guard erasureRootDir.isDirectoryExists else { continue }
                    if let erasureRoot = Data32(fromHexString: erasureRootDir.lastPathComponent) {
                        erasureRoots.append(erasureRoot)
                    }
                }
            }

            return erasureRoots.sorted()
        }.value
    }
}

// MARK: - Helper Methods

extension FilesystemDataStore {
    /// Create directory if it doesn't exist
    ///
    /// Uses Task.detached to run blocking file I/O checks off the actor executor.
    /// This is acceptable here because the task has no cancellation semantics
    /// and we don't need priority inheritance for simple file existence checks.
    private func createDirectoryIfNeeded(_ url: URL) async throws {
        // Capture path as a String to avoid capturing URL in Task.detached
        let path = url.path

        try await Task.detached {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

            if exists {
                guard isDirectory.boolValue else {
                    throw FilesystemDataStoreError.directoryCreationFailed("Path exists but is not a directory: \(path)")
                }
            } else {
                do {
                    try FileManager.default.createDirectory(
                        at: URL(fileURLWithPath: path),
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                } catch {
                    // Verify if it was created by another task
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                        return
                    }
                    throw FilesystemDataStoreError
                        .directoryCreationFailed("Failed to create directory at \(path): \(error.localizedDescription)")
                }
            }
        }.value
    }

    /// Write data atomically (write to temp file, then rename)
    private func writeDataAtomically(to url: URL, data: Data) async throws {
        // Ensure parent directory exists
        let parentDir = url.deletingLastPathComponent()
        try await createDirectoryIfNeeded(parentDir)

        // Capture paths as Strings to avoid capturing URL in Task.detached
        let tempPath = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).tmp").path
        let targetPath = url.path

        // Perform blocking file I/O off the actor executor
        try await Task.detached {
            // Ensure temp file is cleaned up even if an error occurs
            defer {
                try? FileManager.default.removeItem(atPath: tempPath)
            }

            // Create file and write data atomically
            try data.write(to: URL(fileURLWithPath: tempPath))

            // Atomic replace: replaces target if it exists, or moves if it doesn't
            // This preserves atomicity better than remove+move
            #if os(Linux)
                try FileManager.default.replaceItem(
                    at: URL(fileURLWithPath: targetPath),
                    withItemAt: URL(fileURLWithPath: tempPath),
                    backupItemName: nil,
                    options: .usingNewMetadataOnly
                )
            #else
                try FileManager.default.replaceItem(
                    at: URL(fileURLWithPath: targetPath),
                    withItemAt: URL(fileURLWithPath: tempPath),
                    backupItemName: nil,
                    options: .usingNewMetadataOnly,
                    resultingItemURL: nil
                )
            #endif
        }.value
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
        let path = url.path
        let fileManager = FileManager.default

        try await Task.detached {
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(at: URL(fileURLWithPath: path))
            }
        }.value
    }

    /// Remove directory
    private func removeDirectory(at url: URL) async throws {
        let path = url.path
        let fileManager = FileManager.default

        try await Task.detached {
            if fileManager.fileExists(atPath: path) {
                do {
                    try fileManager.removeItem(at: URL(fileURLWithPath: path))
                } catch {
                    logger.error("Failed to remove directory at \(path): \(error.localizedDescription)")
                    throw FilesystemDataStoreError.directoryRemovalFailed("Failed to remove directory: \(path)")
                }
            }
        }.value
    }

    /// Get total size of directory (blocking I/O wrapped in Task.detached)
    ///
    /// Uses Task.detached to run blocking file I/O enumeration off the actor executor.
    /// This prevents blocking the actor when directories contain many files.
    /// Optimized with prefetching of file size attributes to avoid redundant stat calls.
    private func getTotalSize(of url: URL) async throws -> Int {
        // Capture path to avoid capturing URL in Task.detached
        let path = url.path

        return await Task.detached {
            guard FileManager.default.fileExists(atPath: path) else {
                return 0
            }

            var totalSize = 0
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.fileSizeKey],
                options: []
            )

            while let fileURL = enumerator?.nextObject() as? URL {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues?.fileSize {
                    totalSize += fileSize
                }
            }

            return totalSize
        }.value
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
    case directoryCreationFailed(String)
    case directoryRemovalFailed(String)
}

// MARK: - URL Extension

extension URL {
    fileprivate var isDirectoryExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
