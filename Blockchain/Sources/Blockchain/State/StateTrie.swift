import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "StateTrie")

private enum TrieNodeType: UInt8 {
    case branch = 0
    case embeddedLeaf = 1
    case regularLeaf = 2
}

private struct TrieNode {
    let hash: Data32
    let left: Data32 // Original child hash/data
    let right: Data32 // Original child hash/data
    let type: TrieNodeType
    let isNew: Bool
    let rawValue: Data?

    // Constructor for loading from storage (65-byte format: [type][left-32][right-32])
    init(hash: Data32, data: Data, isNew: Bool = false) {
        self.hash = hash
        self.isNew = isNew
        rawValue = nil

        let typeByte = data[relative: 0]
        type = TrieNodeType(rawValue: typeByte) ?? .branch

        left = Data32(data[relative: 1 ..< 33])! // bytes 1-32
        right = Data32(data[relative: 33 ..< 65])! // bytes 33-64
    }

    // Constructor for pure trie operations
    private init(left: Data32, right: Data32, type: TrieNodeType, isNew: Bool, rawValue: Data?) {
        hash = Self.calculateHash(left: left, right: right, type: type)
        self.left = left // Store original data
        self.right = right // Store original data
        self.type = type
        self.isNew = isNew
        self.rawValue = rawValue
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
        data.append(type.rawValue)
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
        let len = Int(left.data[relative: 0])
        let safeLen = min(len, 32)
        return right.data[relative: 0 ..< safeLen]
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

    public init(
        rootHash: Data32,
        backend: StateBackendProtocol,
        enableCache: Bool = true,
        cacheSize: Int = 1000,
        enableWriteBuffer: Bool = true,
        writeBufferSize: Int = 1000,
        writeBufferFlushInterval: TimeInterval = 1.0
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
    }

    /// Read a value from the trie
    /// Phase 2: Reads from in-memory buffer and backend
    /// Note: Does not flush write buffer - reads see pending updates via in-memory 'nodes' map
    public func read(key: Data31) async throws -> Data? {
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

        guard let node = try await get(hash: hash, bypassCache: true, prefetchSiblings: false) else { return nil }

        if node.isBranch {
            let bitValue = Self.bitAt(prefix, position: depth)
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

            // Sequential processing to prevent task explosion
            if let leftNode = try await get(hash: node.left, bypassCache: true, prefetchSiblings: false) {
                result += try await getLeaves(node: leftNode)
            }
            if let rightNode = try await get(hash: node.right, bypassCache: true, prefetchSiblings: false) {
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

            // Sequential processing to prevent task explosion
            if let leftNode = try await get(hash: node.left, bypassCache: true, prefetchSiblings: false) {
                result += try await getLeavesValues(node: leftNode)
            }
            if let rightNode = try await get(hash: node.right, bypassCache: true, prefetchSiblings: false) {
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
            let bitValue = Self.bitAt(key.data, position: depth)
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

    private func get(hash: Data32, bypassCache: Bool = false, prefetchSiblings: Bool = true) async throws -> TrieNode? {
        if hash == Data32() {
            return nil
        }
        let id = hash.data.suffix(31)
        if deleted.contains(id) {
            return nil
        }

        // Check in-memory nodes first (current operation)
        if let node = nodes[id] {
            // Phase 2 Week 4: Prefetch siblings when returning cached node
            if prefetchSiblings, node.isBranch {
                // Prefetch both children asynchronously (don't await)
                Task {
                    _ = try? await get(hash: node.left, bypassCache: false, prefetchSiblings: false)
                    _ = try? await get(hash: node.right, bypassCache: false, prefetchSiblings: false)
                }
            }
            return node
        }

        // Check LRU cache for previously loaded nodes (unless bypassed)
        if !bypassCache, let cache = nodeCache, let cachedNode = cache.get(id) {
            cacheStats?.recordHit()
            // Phase 2 Week 4: Prefetch siblings when returning cached node
            if prefetchSiblings, cachedNode.isBranch {
                // Prefetch both children asynchronously (don't await)
                Task {
                    _ = try? await get(hash: cachedNode.left, bypassCache: false, prefetchSiblings: false)
                    _ = try? await get(hash: cachedNode.right, bypassCache: false, prefetchSiblings: false)
                }
            }
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

        // Phase 2 Week 4: Prefetch siblings after loading from backend
        if prefetchSiblings, node.isBranch {
            // Prefetch both children asynchronously (don't await)
            Task {
                _ = try? await get(hash: node.left, bypassCache: false, prefetchSiblings: false)
                _ = try? await get(hash: node.right, bypassCache: false, prefetchSiblings: false)
            }
        }

        // Don't save loaded nodes to nodes map - they're already persisted
        // and don't need ref count updates (only new nodes do)
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
            // Emit single refUpdate operation with delta
            // This is much more efficient than unrolling into individual increments/decrements
            ops.append(.refUpdate(key: key.suffix(31), delta: Int64(value)))
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

    // MARK: - Iterative Insert (stack-based to prevent stack overflow)

    // Frame structure for tracking traversal path
    private struct InsertPathFrame {
        let hash: Data32
        let depth: UInt8
        let isLeftChild: Bool  // true if we went left, false if right
    }

    private func insert(
        hash: Data32, key: Data31, value: Data, depth: UInt8
    ) async throws -> Data32 {
        // Special case: empty trie
        guard let parentNode = try await get(hash: hash) else {
            let node = TrieNode.leaf(key: key, value: value)
            saveNode(node: node)
            return node.hash
        }

        // If parent is a branch, traverse iteratively to find insertion point
        if parentNode.isBranch {
            // Read parent's children first, then remove parent
            let bitValue = Self.bitAt(key.data, position: depth)
            let initialChildHash = bitValue ? parentNode.right : parentNode.left
            let initialOtherChildHash = bitValue ? parentNode.left : parentNode.right

            removeNode(node: parentNode)

            // Track path: (node_hash, depth, is_left_child, node_snapshot)
            // We need to snapshot the node data since we'll need it later
            var path: [(frame: InsertPathFrame, left: Data32, right: Data32)] = []
            var currentHash = initialChildHash
            var currentDepth = depth + 1

            // Add root to path with saved data
            path.append((
                frame: InsertPathFrame(
                    hash: hash,
                    depth: depth,
                    isLeftChild: !bitValue
                ),
                left: parentNode.left,
                right: parentNode.right
            ))

            // Traverse down to find the leaf node
            while true {
                guard let currentNode = try await get(hash: currentHash) else {
                    throw StateTrieError.invalidData
                }

                if currentNode.isBranch {
                    let bitValue = Self.bitAt(key.data, position: currentDepth)

                    // Remove this branch node as we traverse (prevents memory leaks)
                    removeNode(node: currentNode)

                    // Record path frame with node data
                    path.append((
                        frame: InsertPathFrame(
                            hash: currentHash,
                            depth: currentDepth,
                            isLeftChild: !bitValue
                        ),
                        left: currentNode.left,
                        right: currentNode.right
                    ))

                    // Move to next level
                    currentHash = bitValue ? currentNode.right : currentNode.left
                    currentDepth += 1
                } else {
                    // Found leaf node - insert here
                    let newChildHash = try await insertAtLeaf(
                        existing: currentNode,
                        newKey: key,
                        newValue: value,
                        depth: currentDepth
                    )

                    // Update all ancestors on the path using saved node data
                    return try await updateAncestors(
                        path: path,
                        newChildHash: newChildHash,
                        key: key.data
                    )
                }
            }
        } else {
            // Root is a leaf - insert directly
            return try await insertAtLeaf(
                existing: parentNode,
                newKey: key,
                newValue: value,
                depth: depth
            )
        }
    }

    // Update ancestor nodes after inserting at leaf
    private func updateAncestors(
        path: [(frame: InsertPathFrame, left: Data32, right: Data32)],
        newChildHash: Data32,
        key: Data
    ) async throws -> Data32 {
        var currentChildHash = newChildHash

        // Process path in reverse order (from leaf up to root)
        for (frame, left, right) in path.reversed() {
            let bitValue = Self.bitAt(key, position: frame.depth)
            var newLeft: Data32
            var newRight: Data32

            if bitValue {
                // Right child gets updated
                newLeft = left
                newRight = currentChildHash
            } else {
                // Left child gets updated
                newLeft = currentChildHash
                newRight = right
            }

            let newBranch = TrieNode.branch(left: newLeft, right: newRight)
            saveNode(node: newBranch)
            currentChildHash = newBranch.hash
        }

        return currentChildHash
    }

    // Insert at a leaf node (handles both replacement and divergence)
    private func insertAtLeaf(
        existing: TrieNode,
        newKey: Data31,
        newValue: Data,
        depth: UInt8
    ) async throws -> Data32 {
        // Check if we're updating the same key
        if existing.isLeaf(key: newKey) {
            removeNode(node: existing)
            let newLeaf = TrieNode.leaf(key: newKey, value: newValue)
            saveNode(node: newLeaf)
            return newLeaf.hash
        }

        // Keys diverge - create new branch structure iteratively
        let existingKeyBit = Self.bitAt(existing.left.data[relative: 1...], position: depth)
        let newKeyBit = Self.bitAt(newKey.data, position: depth)

        // Remove existing leaf since it will be replaced
        removeNode(node: existing)

        if existingKeyBit == newKeyBit {
            // Need to go deeper - iterate until we find divergence
            var currentDepth = depth + 1

            while true {
                // Keys are stored in leaf starting at byte 1 (byte 0 is length)
                // So we compare starting from the key data, not including the length byte
                let existingBit = Self.bitAt(existing.left.data[relative: 1...], position: currentDepth)
                let newBit = Self.bitAt(newKey.data, position: currentDepth)

                if existingBit != newBit {
                    // Found divergence point - create branch
                    let newLeaf = TrieNode.leaf(key: newKey, value: newValue)
                    saveNode(node: newLeaf)

                    let newBranch = if existingBit {
                        TrieNode.branch(left: newLeaf.hash, right: existing.hash)
                    } else {
                        TrieNode.branch(left: existing.hash, right: newLeaf.hash)
                    }
                    saveNode(node: newBranch)
                    return newBranch.hash
                }

                currentDepth += 1

                if currentDepth == 0 {
                    // Overflow - keys are identical at all bit positions
                    // This should not happen since isLeaf() check should have caught it
                    // But handle it gracefully by updating the value
                    let newLeaf = TrieNode.leaf(key: newKey, value: newValue)
                    saveNode(node: newLeaf)
                    return newLeaf.hash
                }
            }
        } else {
            // Keys diverge at current level
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

    // MARK: - Delete (iterative to prevent stack overflow)

    // Frame structure for delete traversal
    private struct DeletePathFrame {
        let hash: Data32
        let depth: UInt8
        let isLeftChild: Bool
        let left: Data32
        let right: Data32
    }

    private func delete(hash: Data32, key: Data31, depth: UInt8) async throws -> Data32 {
        let node = try await get(hash: hash)
        guard let node else {
            return Data32()
        }

        if node.isBranch {
            removeNode(node: node)

            // Track path to target with node data
            var path: [DeletePathFrame] = []
            var currentHash = hash
            var currentDepth = depth

            // Find the target node and track path with node data
            while true {
                guard let currentNode = try await get(hash: currentHash) else {
                    return hash // Node not found, return original
                }

                if currentNode.isBranch {
                    let bitValue = Self.bitAt(key.data, position: currentDepth)

                    // Remove and record path frame with node data
                    removeNode(node: currentNode)
                    path.append(DeletePathFrame(
                        hash: currentHash,
                        depth: currentDepth,
                        isLeftChild: !bitValue,
                        left: currentNode.left,
                        right: currentNode.right
                    ))

                    currentHash = bitValue ? currentNode.right : currentNode.left
                    currentDepth += 1
                } else {
                    // Found leaf - check if it matches our key
                    if currentNode.isLeaf(key: key) {
                        // Leaf deleted - now update ancestors using saved data
                        return try await updateAncestorsAfterDelete(
                            path: path,
                            deletedHash: Data32(),
                            key: key
                        )
                    } else {
                        // Key not found - return original hash
                        return hash
                    }
                }
            }
        } else {
            // Root is a leaf - only remove if it matches
            if node.isLeaf(key: key) {
                removeNode(node: node)
                return Data32()
            } else {
                return hash
            }
        }
    }

    // Update ancestors after deleting a leaf
    private func updateAncestorsAfterDelete(
        path: [DeletePathFrame],
        deletedHash: Data32,
        key: Data31
    ) async throws -> Data32 {
        var currentChildHash: Data32 = deletedHash

        // Process path from bottom (deleted leaf's parent) to top (root)
        for frame in path.reversed() {
            let bitValue = Self.bitAt(key.data, position: frame.depth)
            var left: Data32
            var right: Data32

            if bitValue {
                // Right child was deleted
                left = frame.left
                right = currentChildHash
            } else {
                // Left child was deleted
                left = currentChildHash
                right = frame.right
            }

            // Check for collapse opportunities
            if left == Data32(), right == Data32() {
                // Both children empty - this branch becomes empty
                currentChildHash = Data32()
            } else if left == Data32() {
                // Only right child remains - check if we can collapse
                let rightNode = try await get(hash: right)
                if let rightNode, rightNode.isLeaf {
                    // Can collapse: right child is a leaf
                    currentChildHash = right
                } else {
                    // Cannot collapse: right child is a branch
                    let newBranch = TrieNode.branch(left: left, right: right)
                    saveNode(node: newBranch)
                    currentChildHash = newBranch.hash
                }
            } else if right == Data32() {
                // Only left child remains - check if we can collapse
                let leftNode = try await get(hash: left)
                if let leftNode, leftNode.isLeaf {
                    // Can collapse: left child is a leaf
                    currentChildHash = left
                } else {
                    // Cannot collapse: left child is a branch
                    let newBranch = TrieNode.branch(left: left, right: right)
                    saveNode(node: newBranch)
                    currentChildHash = newBranch.hash
                }
            } else {
                // Both children present - no collapse
                let newBranch = TrieNode.branch(left: left, right: right)
                saveNode(node: newBranch)
                currentChildHash = newBranch.hash
            }
        }

        return currentChildHash
    }

    private func removeNode(node: TrieNode) {
        let id = node.hash.data.suffix(31)
        deleted.insert(id)

        // Only remove from nodes map if it's a new node (never persisted)
        // For persisted nodes, we need to keep them in memory until save() processes
        // their reference counts (decrementing children's ref counts)
        if node.isNew {
            nodes.removeValue(forKey: id)
        } else {
            nodes[id] = node
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

    /// bit at i, returns true if it is 1
    private static func bitAt(_ data: Data, position: UInt8) -> Bool {
        let byteIndex = position / 8
        let bitIndex = 7 - (position % 8)
        let byte = data[safeRelative: Int(byteIndex)] ?? 0
        return (byte & (1 << bitIndex)) != 0
    }
}
