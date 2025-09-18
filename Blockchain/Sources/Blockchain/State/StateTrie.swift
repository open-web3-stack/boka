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

    // Constructor for loading from storage (65-byte format: [type][left-32][right-32])
    init(hash: Data32, data: Data, isNew: Bool = false) {
        self.hash = hash
        self.isNew = isNew
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

    public init(rootHash: Data32, backend: StateBackendProtocol) {
        self.rootHash = rootHash
        self.backend = backend
    }

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

    private func get(hash: Data32) async throws -> TrieNode? {
        if hash == Data32() {
            return nil
        }
        let id = hash.data.suffix(31)
        if deleted.contains(id) {
            return nil
        }
        if let node = nodes[id] {
            return node
        }
        guard let data = try await backend.read(key: id) else {
            return nil
        }
        guard data.count == 65 else {
            throw StateTrieError.invalidData
        }
        let node = TrieNode(hash: hash, data: data)
        saveNode(node: node)
        return node
    }

    public func update(_ updates: [(key: Data31, value: Data?)]) async throws {
        // TODO: somehow improve the efficiency of this
        for (key, value) in updates {
            if let value {
                rootHash = try await insert(hash: rootHash, key: key, value: value, depth: 0)
            } else {
                rootHash = try await delete(hash: rootHash, key: key, depth: 0)
            }
        }
    }

    public func save() async throws {
        var ops = [StateBackendOperation]()
        var refChanges = [Data: Int]()

        // process deleted nodes
        for id in deleted {
            guard let node = nodes[id] else {
                continue
            }
            if node.isBranch {
                // assign -1 to not worry about duplicates
                refChanges[node.hash.data.suffix(31)] = -1
                refChanges[node.left.data.suffix(31)] = -1
                refChanges[node.right.data.suffix(31)] = -1
            }
            nodes.removeValue(forKey: id)
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
        }

        // pin root node
        refChanges[rootHash.data.suffix(31), default: 0] += 1

        nodes.removeAll()

        let zeros = Data(repeating: 0, count: 32)
        for (key, value) in refChanges {
            if key == zeros {
                continue
            }
            if value > 0 {
                ops.append(.refIncrement(key: key.suffix(31)))
            } else if value < 0 {
                ops.append(.refDecrement(key: key.suffix(31)))
            }
        }

        try await backend.batchUpdate(ops)
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
        nodes.removeValue(forKey: id)
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
