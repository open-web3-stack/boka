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
    let left: Data32
    let right: Data32
    let type: TrieNodeType
    let isNew: Bool
    let rawValue: Data?

    init(hash: Data32, data: Data64, isNew: Bool = false) {
        self.hash = hash
        left = Data32(data.data.prefix(32))!
        right = Data32(data.data.suffix(32))!
        self.isNew = isNew
        rawValue = nil
        switch data.data.first! & 0b1100_0000 {
        case 0b1000_0000:
            type = .embeddedLeaf
        case 0b1100_0000:
            type = .regularLeaf
        default:
            type = .branch
        }
    }

    private init(left: Data32, right: Data32, type: TrieNodeType, isNew: Bool, rawValue: Data?) {
        hash = Blake2b256.hash(left.data, right.data)
        self.left = left
        self.right = right
        self.type = type
        self.isNew = isNew
        self.rawValue = rawValue
    }

    var encodedData: Data64 {
        Data64(left.data + right.data)!
    }

    var isBranch: Bool {
        type == .branch
    }

    var isLeaf: Bool {
        !isBranch
    }

    func isLeaf(key: Data32) -> Bool {
        isLeaf && left.data[relative: 1 ..< 32] == key.data.prefix(31)
    }

    var value: Data? {
        if let rawValue {
            return rawValue
        }
        guard type == .embeddedLeaf else {
            return nil
        }
        let len = left.data.first! & 0b0011_1111
        return right.data[relative: 0 ..< Int(len)]
    }

    static func leaf(key: Data32, value: Data) -> TrieNode {
        var newKey = Data(capacity: 32)
        if value.count <= 32 {
            newKey.append(0b1000_0000 | UInt8(value.count))
            newKey += key.data.prefix(31)
            let newValue = value + Data(repeating: 0, count: 32 - value.count)
            return .init(left: Data32(newKey)!, right: Data32(newValue)!, type: .embeddedLeaf, isNew: true, rawValue: value)
        }
        newKey.append(0b1100_0000)
        newKey += key.data.prefix(31)
        return .init(left: Data32(newKey)!, right: value.blake2b256hash(), type: .regularLeaf, isNew: true, rawValue: value)
    }

    static func branch(left: Data32, right: Data32) -> TrieNode {
        var left = left.data
        left[left.startIndex] = left[left.startIndex] & 0b0111_1111 // clear the highest bit
        return .init(left: Data32(left)!, right: right, type: .branch, isNew: true, rawValue: nil)
    }
}

public enum StateTrieError: Error {
    case invalidData
    case invalidParent
}

public actor StateTrie: Sendable {
    private let backend: StateBackendProtocol
    public private(set) var rootHash: Data32
    private var nodes: [Data: TrieNode] = [:]
    private var deleted: Set<Data> = []

    public init(rootHash: Data32, backend: StateBackendProtocol) {
        self.rootHash = rootHash
        self.backend = backend
    }

    public func read(key: Data32) async throws -> Data? {
        let node = try await find(hash: rootHash, key: key, depth: 0)
        guard let node else {
            return nil
        }
        if let value = node.value {
            return value
        }
        return try await backend.readValue(hash: node.right)
    }

    private func find(hash: Data32, key: Data32, depth: UInt8) async throws -> TrieNode? {
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

        guard let data64 = Data64(data) else {
            throw StateTrieError.invalidData
        }

        let node = TrieNode(hash: hash, data: data64)
        saveNode(node: node)
        return node
    }

    public func update(_ updates: [(key: Data32, value: Data?)]) async throws {
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
            ops.append(.write(key: node.hash.data.suffix(31), value: node.encodedData.data))
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
        hash: Data32, key: Data32, value: Data, depth: UInt8
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

    private func insertLeafNode(existing: TrieNode, newKey: Data32, newValue: Data, depth: UInt8) async throws -> Data32 {
        if existing.isLeaf(key: newKey) {
            // update existing leaf
            let newLeaf = TrieNode.leaf(key: newKey, value: newValue)
            saveNode(node: newLeaf)
            return newLeaf.hash
        }

        let existingKeyBit = bitAt(existing.left.data[1...], position: depth)
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

    private func delete(hash: Data32, key: Data32, depth: UInt8) async throws -> Data32 {
        let node = try await get(hash: hash).unwrap(orError: StateTrieError.invalidParent)

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
            }

            let newBranch = TrieNode.branch(left: left, right: right)
            saveNode(node: newBranch)
            return newBranch.hash
        } else {
            // leaf
            return Data32()
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
        deleted.remove(id) // TODO: maybe this is not needed
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
