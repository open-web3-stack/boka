import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "StateTrie")

private enum TrieNodeType {
    case branch
    case embeddedLeaf
    case regularLeaf
}

private struct TrieNode {
    let hash: Data32
    let left: Data32 // Original child hash/data
    let right: Data32 // Original child hash/data
    let type: TrieNodeType
    let isNew: Bool
    let rawValue: Data?
    let hashVersion: UInt64 // Track hash version for cache invalidation

    // Constructor for loading from storage (65-byte format: [type][left-32][right-32])
    init(hash: Data32, data: Data, isNew: Bool = false, hashVersion: UInt64 = 0) {
        self.hash = hash
        self.isNew = isNew
        self.hashVersion = hashVersion
        rawValue = nil

        let typeByte = data[relative: 0]
        switch typeByte {
        case 0:
            type = .branch
        case 1:
            type = .embeddedLeaf
        case 2:
            type = .regularLeaf
        default:
            type = .branch
        }

        left = Data32(data[relative: 1 ..< 33])! // bytes 1-32
        right = Data32(data[relative: 33 ..< 65])! // bytes 33-64
    }

    // Constructor for pure trie operations
    private init(left: Data32, right: Data32, type: TrieNodeType, isNew: Bool, rawValue: Data?, hashVersion: UInt64 = 0) {
        hash = Self.calculateHash(left: left, right: right, type: type)
        self.left = left // Store original data
        self.right = right // Store original data
        self.type = type
        self.isNew = isNew
        self.rawValue = rawValue
        self.hashVersion = hashVersion
    }

    // JAM spec compliant hash calculation
    private static func calculateHash(left: Data32, right: Data32, type: TrieNodeType) -> Data32 {
        switch type {
        case .branch:
            var leftForHashing = left.data
            leftForHashing[leftForHashing.startIndex] = leftForHashing[leftForHashing.startIndex] & 0b0111_1111
            return Blake2b256.hash(leftForHashing, right.data)
        case .embeddedLeaf:
            var leftForHashing = left.data
            let valueLength = leftForHashing[leftForHashing.startIndex]
            leftForHashing[leftForHashing.startIndex] = 0b1000_0000 | valueLength
            return Blake2b256.hash(leftForHashing, right.data)
        case .regularLeaf:
            var leftForHashing = left.data
            leftForHashing[leftForHashing.startIndex] = 0b1100_0000
            return Blake2b256.hash(leftForHashing, right.data)
        }
    }

    // New 65-byte storage format: [type:1][left:32][right:32]
    var storageData: Data {
        var data = Data(capacity: 65)

        switch type {
        case .branch: data.append(0)
        case .embeddedLeaf: data.append(1)
        case .regularLeaf: data.append(2)
        }

        data.append(left.data)
        data.append(right.data)

        return data
    }

    var isBranch: Bool {
        type == .branch
    }

    var isLeaf: Bool {
        !isBranch
    }

    func isLeaf(key: Data31) -> Bool {
        isLeaf && left.data[relative: 1 ..< 32] == key.data
    }

    var value: Data? {
        if let rawValue {
            return rawValue
        }
        guard type == .embeddedLeaf else {
            return nil
        }
        // For embedded leaves: length is stored in first byte
        let len = left.data[relative: 0]
        return right.data[relative: 0 ..< Int(len)]
    }

    static func leaf(key: Data31, value: Data) -> TrieNode {
        if value.count <= 32 {
            // Embedded leaf: store length + key, padded value
            var keyData = Data(capacity: 32)
            keyData.append(UInt8(value.count)) // Store length in first byte
            keyData += key.data
            let paddedValue = value + Data(repeating: 0, count: 32 - value.count)
            return .init(left: Data32(keyData)!, right: Data32(paddedValue)!, type: .embeddedLeaf, isNew: true, rawValue: value)
        } else {
            // Regular leaf: store key, value hash
            var keyData = Data(capacity: 32)
            keyData.append(0x00) // Placeholder for first byte
            keyData += key.data
            return .init(left: Data32(keyData)!, right: value.blake2b256hash(), type: .regularLeaf, isNew: true, rawValue: value)
        }
    }

    static func branch(left: Data32, right: Data32) -> TrieNode {
        .init(left: left, right: right, type: .branch, isNew: true, rawValue: nil)
    }
}

public enum StateTrieError: Error {
    case invalidData
    case invalidParent
}

public actor StateTrie {
    private let backend: StateBackendProtocol
    public private(set) var rootHash: Data32
    private var nodes: [Data: TrieNode] = [:]
    private var deleted: Set<Data> = []
    private var lastSavedRootHash: Data32 // Track last saved root for proper ref counting

    // Performance optimization: LRU cache for frequently accessed nodes
    private let nodeCache: LRUCache<Data, TrieNode>?
    private let cacheStats: CacheStatsTracker?

    // Performance optimization: Write buffering for batched I/O
    private let writeBuffer: WriteBuffer?
    private let enableWriteBuffer: Bool

    // Performance optimization: Parallel hash computation for batch operations
    private let enableParallelHash: Bool
    private let maxParallelism: Int

    public init(
        rootHash: Data32,
        backend: StateBackendProtocol,
        enableCache: Bool = true,
        cacheSize: Int = 1000,
        enableWriteBuffer: Bool = true,
        writeBufferSize: Int = 1000,
        writeBufferFlushInterval: TimeInterval = 1.0,
        enableParallelHash: Bool = true,
        maxParallelism: Int = ProcessInfo.processInfo.processorCount
    ) {
        self.rootHash = rootHash
        self.backend = backend
        lastSavedRootHash = rootHash // Initialize with current root
        nodeCache = enableCache ? LRUCache(capacity: cacheSize) : nil
        cacheStats = enableCache ? CacheStatsTracker() : nil
        self.enableWriteBuffer = enableWriteBuffer
        writeBuffer = enableWriteBuffer ? WriteBuffer(
            maxBufferSize: writeBufferSize,
            flushInterval: writeBufferFlushInterval
        ) : nil
        self.enableParallelHash = enableParallelHash
        self.maxParallelism = maxParallelism
    }

    /// Read a value from the trie
    /// Phase 2: Flushes write buffer before read to ensure consistency
    public func read(key: Data31) async throws -> Data? {
        // Flush buffer to ensure we read latest data
        // Note: While StateTrie checks the in-memory 'nodes' map first, flushing ensures
        // we see all updates including those that might have been partially applied.
        // This is conservative but ensures correctness. For read-heavy workloads,
        // consider increasing write buffer size or using separate read/write tries.
        try await flushWriteBuffer()

        let node = try await find(hash: rootHash, key: key, depth: 0)
        guard let node else {
            return nil
        }
        if let value = node.value {
            return value
        }
        return try await backend.readValue(hash: node.right)
    }

    /// Collect all keys matching a given prefix by traversing the trie
    public func getKeys(matchingPrefix prefix: Data, bitsCount: UInt8) async throws -> [Data31] {
        // 31 bytes = 248 bits max
        guard bitsCount <= 248 else { return [] }

        // Navigate to the node where the prefix path ends
        guard let startNode = try await findByPrefix(hash: rootHash, prefix: prefix, bitsCount: bitsCount, depth: 0) else {
            return []
        }

        // Collect all leaf keys from this subtree
        return try await getLeaves(node: startNode)
    }

    /// Collect all keys with their values matching a given prefix by traversing the trie
    public func getKeyValues(matchingPrefix prefix: Data, bitsCount: UInt8) async throws -> [(key: Data31, value: Data)] {
        // 31 bytes = 248 bits max
        guard bitsCount <= 248 else { return [] }

        // Navigate to the node where the prefix path ends
        guard let startNode = try await findByPrefix(hash: rootHash, prefix: prefix, bitsCount: bitsCount, depth: 0) else {
            return []
        }

        // Collect all leaf keys with values from this subtree
        return try await getLeavesValues(node: startNode)
    }

    /// Navigate the trie following the prefix bits to find the subtree root
    private func findByPrefix(hash: Data32, prefix: Data, bitsCount: UInt8, depth: UInt8) async throws -> TrieNode? {
        guard depth < bitsCount else {
            // Reached the end of prefix, return this node
            return try await get(hash: hash, bypassCache: true)
        }

        guard let node = try await get(hash: hash, bypassCache: true) else { return nil }

        if node.isBranch {
            let bitValue = bitAt(prefix, position: depth)
            let childHash = bitValue ? node.right : node.left
            return try await findByPrefix(hash: childHash, prefix: prefix, bitsCount: bitsCount, depth: depth + 1)
        } else {
            // Hit a leaf before consuming all prefix bits - verify it matches
            let leafKey = Data(node.left.data[relative: 1 ..< 32])

            // Check byte-aligned portion
            let prefixBytes = (Int(bitsCount) + 7) / 8
            guard leafKey.prefix(prefixBytes).starts(with: prefix.prefix(prefixBytes)) else {
                return nil
            }

            // If not byte-aligned, check remaining bits
            if bitsCount % 8 != 0 {
                let lastByte = leafKey[safeRelative: prefixBytes - 1] ?? 0
                let prefixLastByte = prefix[safeRelative: prefixBytes - 1] ?? 0
                let mask = UInt8(0xFF << (8 - (bitsCount % 8)))
                guard (lastByte & mask) == (prefixLastByte & mask) else {
                    return nil
                }
            }

            return node
        }
    }

    /// Recursively collect all leaf keys from a subtree
    private func getLeaves(node: TrieNode) async throws -> [Data31] {
        if node.isBranch {
            var result: [Data31] = []
            if let leftNode = try await get(hash: node.left, bypassCache: true) {
                result += try await getLeaves(node: leftNode)
            }
            if let rightNode = try await get(hash: node.right, bypassCache: true) {
                result += try await getLeaves(node: rightNode)
            }
            return result
        } else {
            // Leaf node - extract key
            let keyData = Data(node.left.data[relative: 1 ..< 32])
            return Data31(keyData).map { [$0] } ?? []
        }
    }

    /// Recursively collect all leaf keys with their values from a subtree
    private func getLeavesValues(node: TrieNode) async throws -> [(key: Data31, value: Data)] {
        if node.isBranch {
            var result: [(key: Data31, value: Data)] = []
            if let leftNode = try await get(hash: node.left, bypassCache: true) {
                result += try await getLeavesValues(node: leftNode)
            }
            if let rightNode = try await get(hash: node.right, bypassCache: true) {
                result += try await getLeavesValues(node: rightNode)
            }
            return result
        } else {
            // Leaf node - extract key and value
            let keyData = Data(node.left.data[relative: 1 ..< 32])
            guard let key = Data31(keyData) else { return [] }

            // Get value: embedded leaves have it in node.value, regular leaves need backend fetch
            let value: Data
            if let embeddedValue = node.value {
                value = embeddedValue
            } else {
                // Regular leaf - fetch value from backend
                guard let fetchedValue = try await backend.readValue(hash: node.right) else {
                    return []
                }
                value = fetchedValue
            }

            return [(key: key, value: value)]
        }
    }

    private func find(hash: Data32, key: Data31, depth: UInt8) async throws -> TrieNode? {
        guard let node = try await get(hash: hash) else {
            return nil
        }
        if node.isBranch {
            let bitValue = bitAt(key.data, position: depth)
            if bitValue {
                return try await find(hash: node.right, key: key, depth: depth + 1)
            } else {
                return try await find(hash: node.left, key: key, depth: depth + 1)
            }
        } else if node.isLeaf(key: key) {
            return node
        }
        return nil
    }

    private func get(hash: Data32, bypassCache: Bool = false) async throws -> TrieNode? {
        if hash == Data32() {
            return nil
        }
        let id = hash.data.suffix(31)
        if deleted.contains(id) {
            return nil
        }

        // Check in-memory nodes first (current operation)
        if let node = nodes[id] {
            return node
        }

        // Check LRU cache for previously loaded nodes (unless bypassed)
        if !bypassCache, let cache = nodeCache, let cachedNode = cache.get(id) {
            cacheStats?.recordHit()
            return cachedNode
        }

        // Load from backend
        guard let data = try await backend.read(key: id) else {
            if !bypassCache {
                cacheStats?.recordMiss()
            }
            return nil
        }
        if !bypassCache {
            cacheStats?.recordMiss()
        }
        guard data.count == 65 else {
            throw StateTrieError.invalidData
        }
        let node = TrieNode(hash: hash, data: data)

        // Cache the node for future access
        if let cache = nodeCache {
            cache.put(id, value: node)
        }

        saveNode(node: node)
        return node
    }

    /// Update trie with multiple key-value pairs
    /// Performance optimizations:
    /// - Write buffering: Phase 2 - Buffer updates before batch I/O
    /// - Parallel processing: Use TaskGroup for independent updates (future)
    /// - Cache optimization: Keep recently accessed nodes in memory
    public func update(_ updates: [(key: Data31, value: Data?)]) async throws {
        // If write buffering is enabled, use buffered updates
        if enableWriteBuffer, let buffer = writeBuffer {
            try await updateBuffered(updates, buffer: buffer)
        } else {
            // Original immediate update path
            for (key, value) in updates {
                if let value {
                    rootHash = try await insert(hash: rootHash, key: key, value: value, depth: 0)
                } else {
                    rootHash = try await delete(hash: rootHash, key: key, depth: 0)
                }
            }
        }
    }

    /// Phase 2: Buffered update implementation
    /// Accumulates updates in buffer and flushes when necessary
    private func updateBuffered(_ updates: [(key: Data31, value: Data?)], buffer: WriteBuffer) async throws {
        for (key, value) in updates {
            // Add to buffer (synchronous since WriteBuffer is no longer an actor)
            let shouldFlush = buffer.add(key: key, value: value)

            // Apply update to in-memory trie
            if let value {
                rootHash = try await insert(hash: rootHash, key: key, value: value, depth: 0)
            } else {
                rootHash = try await delete(hash: rootHash, key: key, depth: 0)
            }

            // Flush if buffer is full or time interval elapsed
            if shouldFlush {
                try await flushWriteBuffer()
            }
        }
    }

    public func save() async throws {
        var ops = [StateBackendOperation]()
        var refChanges = [Data: Int]()

        // Decrement reference count of old root hash if it changed
        if lastSavedRootHash != rootHash {
            refChanges[lastSavedRootHash.data.suffix(31), default: 0] -= 1
        }

        // process deleted nodes
        for id in deleted {
            guard let node = nodes[id] else {
                continue
            }
            if node.isBranch {
                // Decrement reference counts for children of deleted branch nodes
                // Note: We don't decrement the node's own ref count here - that's
                // handled by its parent when the parent is processed (or when the
                // root changes). We only decrement the children that this node
                // was referencing.
                // Use -= to properly accumulate if multiple deleted nodes share children
                refChanges[node.left.data.suffix(31), default: 0] -= 1
                refChanges[node.right.data.suffix(31), default: 0] -= 1
            }
            nodes.removeValue(forKey: id)

            // Invalidate from cache when deleted
            if let cache = nodeCache {
                cache.remove(id)
            }
        }
        deleted.removeAll()

        for node in nodes.values where node.isNew {
            ops.append(.write(key: node.hash.data.suffix(31), value: node.storageData))
            if node.type == .regularLeaf {
                try ops.append(.writeRawValue(key: node.right, value: node.rawValue.unwrap()))
            }
            if node.isBranch {
                refChanges[node.left.data.suffix(31), default: 0] += 1
                refChanges[node.right.data.suffix(31), default: 0] += 1
            }

            // Update cache with new nodes
            if let cache = nodeCache {
                cache.put(node.hash.data.suffix(31), value: node)
            }
        }

        // pin root node
        refChanges[rootHash.data.suffix(31), default: 0] += 1

        nodes.removeAll()

        let zeros = Data(repeating: 0, count: 31) // Keys are 31 bytes (suffix of Data32)
        for (key, value) in refChanges {
            if key == zeros {
                continue
            }
            // Emit multiple operations for deltas with magnitude > 1
            // since each refIncrement/refDecrement only changes count by 1
            if value > 0 {
                for _ in 0 ..< value {
                    ops.append(.refIncrement(key: key.suffix(31)))
                }
            } else if value < 0 {
                for _ in 0 ..< -value {
                    ops.append(.refDecrement(key: key.suffix(31)))
                }
            }
        }

        try await backend.batchUpdate(ops)

        // Update last saved root hash after successful batch update
        lastSavedRootHash = rootHash
    }

    /// Get cache statistics for monitoring and debugging
    public func getCacheStats() async -> CacheStatsTracker.CacheStatistics? {
        guard let stats = cacheStats else {
            return nil
        }
        return stats.current
    }

    /// Clear the LRU cache (useful for testing or memory management)
    public func clearCache() {
        nodeCache?.removeAll()
        cacheStats?.reset()
    }

    // MARK: - Phase 2: Write Buffering Methods

    /// Flush the write buffer, persisting all buffered updates to storage
    /// This is called automatically when buffer is full or flush interval elapses
    /// Can also be called manually for immediate persistence
    public func flushWriteBuffer() async throws {
        guard enableWriteBuffer, let buffer = writeBuffer else {
            return
        }

        // Only flush if there's something to flush (synchronous check)
        guard !buffer.isEmpty else {
            return
        }

        // Save current state (this is where actual I/O happens)
        try await save()

        // Clear the buffer after successful save (synchronous)
        _ = buffer.flush()
    }

    /// Manually trigger a flush of the write buffer
    /// Use this to ensure all updates are persisted before critical operations
    public func flush() async throws {
        try await flushWriteBuffer()
    }

    /// Get write buffer statistics for monitoring and debugging
    public func getWriteBufferStats() -> WriteBufferStats? {
        guard let buffer = writeBuffer else {
            return nil
        }
        return buffer.stats
    }

    /// Clear the write buffer without flushing (use with caution - data loss!)
    /// Only useful for testing or error recovery
    public func clearWriteBuffer() {
        writeBuffer?.clear()
    }

    private func insert(
        hash: Data32, key: Data31, value: Data, depth: UInt8
    ) async throws -> Data32 {
        guard let parent = try await get(hash: hash) else {
            let node = TrieNode.leaf(key: key, value: value)
            saveNode(node: node)
            return node.hash
        }

        if parent.isBranch {
            removeNode(hash: hash)

            let bitValue = bitAt(key.data, position: depth)
            var left = parent.left
            var right = parent.right
            if bitValue {
                right = try await insert(hash: parent.right, key: key, value: value, depth: depth + 1)
            } else {
                left = try await insert(hash: parent.left, key: key, value: value, depth: depth + 1)
            }
            let newBranch = TrieNode.branch(left: left, right: right)
            saveNode(node: newBranch)
            return newBranch.hash
        } else {
            // leaf
            return try await insertLeafNode(existing: parent, newKey: key, newValue: value, depth: depth)
        }
    }

    private func insertLeafNode(existing: TrieNode, newKey: Data31, newValue: Data, depth: UInt8) async throws -> Data32 {
        if existing.isLeaf(key: newKey) {
            // update existing leaf
            let newLeaf = TrieNode.leaf(key: newKey, value: newValue)
            saveNode(node: newLeaf)
            return newLeaf.hash
        }

        let existingKeyBit = bitAt(existing.left.data[relative: 1...], position: depth)
        let newKeyBit = bitAt(newKey.data, position: depth)

        if existingKeyBit == newKeyBit {
            // need to go deeper
            let childNodeHash = try await insertLeafNode(
                existing: existing, newKey: newKey, newValue: newValue, depth: depth + 1
            )
            let newBranch = if existingKeyBit {
                TrieNode.branch(left: Data32(), right: childNodeHash)
            } else {
                TrieNode.branch(left: childNodeHash, right: Data32())
            }
            saveNode(node: newBranch)
            return newBranch.hash
        } else {
            let newLeaf = TrieNode.leaf(key: newKey, value: newValue)
            saveNode(node: newLeaf)
            let newBranch = if existingKeyBit {
                TrieNode.branch(left: newLeaf.hash, right: existing.hash)
            } else {
                TrieNode.branch(left: existing.hash, right: newLeaf.hash)
            }
            saveNode(node: newBranch)
            return newBranch.hash
        }
    }

    private func delete(hash: Data32, key: Data31, depth: UInt8) async throws -> Data32 {
        let node = try await get(hash: hash)
        guard let node else {
            return Data32()
        }

        if node.isBranch {
            removeNode(hash: hash)

            let bitValue = bitAt(key.data, position: depth)
            var left = node.left
            var right = node.right

            if bitValue {
                right = try await delete(hash: node.right, key: key, depth: depth + 1)
            } else {
                left = try await delete(hash: node.left, key: key, depth: depth + 1)
            }

            if left == Data32(), right == Data32() {
                // this branch is empty
                return Data32()
            } else if left == Data32() {
                // only right child remains - check if we can collapse
                let rightNode = try await get(hash: right)
                if let rightNode, rightNode.isLeaf {
                    // Can collapse: right child is a leaf
                    return right
                } else {
                    // Cannot collapse: right child is a branch that needs to maintain its depth
                    let newBranch = TrieNode.branch(left: left, right: right)
                    saveNode(node: newBranch)
                    return newBranch.hash
                }
            } else if right == Data32() {
                // only left child remains - check if we can collapse
                let leftNode = try await get(hash: left)
                if let leftNode, leftNode.isLeaf {
                    // Can collapse: left child is a leaf
                    return left
                } else {
                    // Cannot collapse: left child is a branch that needs to maintain its depth
                    let newBranch = TrieNode.branch(left: left, right: right)
                    saveNode(node: newBranch)
                    return newBranch.hash
                }
            }

            let newBranch = TrieNode.branch(left: left, right: right)
            saveNode(node: newBranch)
            return newBranch.hash
        } else {
            // leaf - only remove if the leaf matches the key we're deleting
            if node.isLeaf(key: key) {
                removeNode(hash: hash)
                return Data32()
            } else {
                return hash
            }
        }
    }

    private func removeNode(hash: Data32) {
        let id = hash.data.suffix(31)
        deleted.insert(id)

        // Only remove from nodes map if it's a new node (never persisted)
        // For persisted nodes, we need to keep them in memory until save() processes
        // their reference counts (decrementing children's ref counts)
        if let node = nodes[id], node.isNew {
            nodes.removeValue(forKey: id)
        }
    }

    private func saveNode(node: TrieNode) {
        let id = node.hash.data.suffix(31)
        nodes[id] = node
        deleted.remove(id)
    }

    public func debugPrint() async throws {
        func printNode(_ hash: Data32, depth: UInt8) async throws {
            let prefix = String(repeating: " ", count: Int(depth))
            if hash == Data32() {
                logger.info("\(prefix) nil")
                return
            }
            let node = try await get(hash: hash)
            guard let node else {
                return logger.info("\(prefix) ????")
            }
            logger.info("\(prefix)\(node.hash.toHexString()) \(node.type)")
            if node.isBranch {
                logger.info("\(prefix) left:")
                try await printNode(node.left, depth: depth + 1)

                logger.info("\(prefix) right:")
                try await printNode(node.right, depth: depth + 1)
            } else {
                logger.info("\(prefix) key: \(node.left.toHexString())")
                if let value = node.value {
                    logger.info("\(prefix) value: \(value.toHexString())")
                }
            }
        }

        logger.info("Root hash: \(rootHash.toHexString())")
        try await printNode(rootHash, depth: 0)
    }
}

/// bit at i, returns true if it is 1
private func bitAt(_ data: Data, position: UInt8) -> Bool {
    let byteIndex = position / 8
    let bitIndex = 7 - (position % 8)
    let byte = data[safeRelative: Int(byteIndex)] ?? 0
    return (byte & (1 << bitIndex)) != 0
}
