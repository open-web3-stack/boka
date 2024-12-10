import Blockchain
import Codec
import Foundation
import RocksDBSwift
import Utils

public enum RocksDBBackendError: Error {
    case genesisHashMismatch(expected: Data32, actual: Data)
}

public final class RocksDBBackend: Sendable {
    private let config: ProtocolConfigRef
    private let db: RocksDB<StoreId>
    private let meta: Store<StoreId, NoopCoder>
    private let blocks: Store<StoreId, JamCoder<Data32, BlockRef>>
    private let blockHashByTimeslot: Store<StoreId, JamCoder<TimeslotIndex, Set<Data32>>>
    private let blockHashByNumber: Store<StoreId, JamCoder<UInt32, Set<Data32>>>
    private let blockNumberByHash: Store<StoreId, JamCoder<Data32, UInt32>>
    private let stateTrie: Store<StoreId, JamCoder<Data, Data>>
    private let stateValue: Store<StoreId, JamCoder<Data32, Data>>
    private let stateRefs: Store<StoreId, JamCoder<Data, UInt32>>
    private let stateRefsRaw: Store<StoreId, JamCoder<Data32, UInt32>>

    public let genesisBlockHash: Data32

    public init(path: URL, config: ProtocolConfigRef, genesisBlock: BlockRef, genesisStateData: [Data32: Data]) async throws {
        self.config = config
        db = try RocksDB(path: path)
        meta = Store(db: db, column: .meta, coder: NoopCoder())
        blocks = Store(db: db, column: .blocks, coder: JamCoder(config: config))
        blockHashByTimeslot = Store(db: db, column: .blockIndexes, coder: JamCoder(config: config, prefix: Data([0])))
        blockHashByNumber = Store(db: db, column: .blockIndexes, coder: JamCoder(config: config, prefix: Data([1])))
        blockNumberByHash = Store(db: db, column: .blockIndexes, coder: JamCoder(config: config, prefix: Data([2])))
        stateTrie = Store(db: db, column: .state, coder: JamCoder(config: config, prefix: Data([0])))
        stateValue = Store(db: db, column: .state, coder: JamCoder(config: config, prefix: Data([1])))
        stateRefs = Store(db: db, column: .stateRefs, coder: JamCoder(config: config, prefix: Data([0])))
        stateRefsRaw = Store(db: db, column: .stateRefs, coder: JamCoder(config: config, prefix: Data([1])))

        genesisBlockHash = genesisBlock.hash

        let genesis = try meta.get(key: MetaKey.genesisHash.key)
        if let genesis {
            guard genesis == genesisBlockHash.data else {
                throw RocksDBBackendError.genesisHashMismatch(expected: genesisBlockHash, actual: genesis)
            }
        } else {
            // must be a new db
            try meta.put(key: MetaKey.genesisHash.key, value: genesisBlockHash.data)
            try await add(block: genesisBlock)
            let backend = StateBackend(self, config: config, rootHash: Data32())
            try await backend.writeRaw(Array(genesisStateData))
            try setHeads([genesisBlockHash])
            try await setFinalizedHead(hash: genesisBlockHash)
        }
    }

    private func setHeads(_ heads: Set<Data32>) throws {
        try meta.put(key: MetaKey.heads.key, value: JamEncoder.encode(heads))
    }
}

extension RocksDBBackend: BlockchainDataProviderProtocol {
    public func hasBlock(hash: Data32) async throws -> Bool {
        try blocks.exists(key: hash)
    }

    public func hasState(hash: Data32) async throws -> Bool {
        try stateTrie.exists(key: hash.data)
    }

    public func isHead(hash: Data32) async throws -> Bool {
        try await getHeads().contains(hash)
    }

    public func getBlockNumber(hash: Data32) async throws -> UInt32? {
        try blockNumberByHash.get(key: hash)
    }

    public func getHeader(hash: Data32) async throws -> HeaderRef? {
        try await getBlock(hash: hash)?.header.asRef()
    }

    public func getBlock(hash: Data32) async throws -> BlockRef? {
        try blocks.get(key: hash)
    }

    public func getState(hash: Data32) async throws -> StateRef? {
        try await State(backend: StateBackend(self, config: config, rootHash: hash)).asRef()
    }

    public func getFinalizedHead() async throws -> Data32? {
        try meta.get(key: MetaKey.finalizedHead.key).flatMap { Data32($0) }
    }

    public func getHeads() async throws -> Set<Data32> {
        let data = try meta.get(key: MetaKey.heads.key)
        guard let data else {
            return []
        }
        return try JamDecoder.decode(Set<Data32>.self, from: data)
    }

    public func getBlockHash(byTimeslot: TimeslotIndex) async throws -> Set<Data32> {
        try blockHashByTimeslot.get(key: byTimeslot) ?? Set()
    }

    public func getBlockHash(byNumber: UInt32) async throws -> Set<Data32> {
        try blockHashByNumber.get(key: byNumber) ?? Set()
    }

    public func add(block: BlockRef) async throws {
        // TODO: batch put

        try blocks.put(key: block.hash, value: block)
        var timeslotHashes = try await getBlockHash(byTimeslot: block.header.timeslot)
        timeslotHashes.insert(block.hash)
        try blockHashByTimeslot.put(key: block.header.timeslot, value: timeslotHashes)

        let blockNumber = if let number = try await getBlockNumber(hash: block.header.parentHash) {
            number + 1
        } else {
            UInt32(0)
        }

        var numberHashes = try await getBlockHash(byNumber: blockNumber)
        numberHashes.insert(block.hash)
        try blockHashByNumber.put(key: blockNumber, value: numberHashes)

        try blockNumberByHash.put(key: block.hash, value: blockNumber)
    }

    public func add(state _: StateRef) async throws {
        // nothing to do
    }

    public func setFinalizedHead(hash: Data32) async throws {
        try meta.put(key: MetaKey.finalizedHead.key, value: hash.data)
    }

    public func updateHead(hash: Data32, parent: Data32) async throws {
        var heads = try await getHeads()

        // parent needs to be either
        // - existing head
        // - known block
        if heads.remove(parent) == nil {
            if try await !hasBlock(hash: parent) {
                throw BlockchainDataProviderError.noData(hash: parent)
            }
        }

        heads.insert(hash)

        try meta.put(key: MetaKey.heads.key, value: JamEncoder.encode(heads))
    }

    public func remove(hash: Data32) async throws {
        // TODO: batch delete

        try blocks.delete(key: hash)

        if let block = try await getBlock(hash: hash) {
            try blockHashByTimeslot.delete(key: block.header.timeslot)
        }

        if let blockNumber = try await getBlockNumber(hash: hash) {
            try blockHashByNumber.delete(key: blockNumber)
        }
        try blockNumberByHash.delete(key: hash)
    }
}

extension RocksDBBackend: StateBackendProtocol {
    public func read(key: Data) async throws -> Data? {
        try stateTrie.get(key: key)
    }

    public func readAll(prefix: Data, startKey: Data?, limit: UInt32?) async throws -> [(key: Data, value: Data)] {
        let snapshot = db.createSnapshot()
        let readOptions = ReadOptions()
        readOptions.setSnapshot(snapshot)

        let iterator = db.createIterator(column: .state, readOptions: readOptions)
        iterator.seek(to: startKey ?? prefix)

        var ret = [(key: Data, value: Data)]()
        if let limit {
            ret.reserveCapacity(Int(limit))
        }
        for _ in 0 ..< (limit ?? .max) {
            iterator.next()
            if let (key, value) = iterator.read() {
                if key.starts(with: prefix) {
                    ret.append((key, value))
                } else {
                    break
                }
            } else {
                break
            }
        }
        return ret
    }

    public func batchUpdate(_ updates: [StateBackendOperation]) async throws {
        // TODO: implement this using merge operator to perform atomic increment
        // so we can do the whole thing in a single batch
        for update in updates {
            switch update {
            case let .write(key, value):
                try stateTrie.put(key: key, value: value)
            case let .writeRawValue(key, value):
                try stateValue.put(key: key, value: value)
                let refCount = try stateRefsRaw.get(key: key) ?? 0
                try stateRefsRaw.put(key: key, value: refCount + 1)
            case let .refIncrement(key):
                let refCount = try stateRefs.get(key: key) ?? 0
                try stateRefs.put(key: key, value: refCount + 1)
            case let .refDecrement(key):
                let refCount = try stateRefs.get(key: key) ?? 0
                try stateRefs.put(key: key, value: refCount - 1)
            }
        }
    }

    public func readValue(hash: Data32) async throws -> Data? {
        try stateValue.get(key: hash)
    }

    public func gc(callback _: @Sendable (Data) -> Data32?) async throws {
        // TODO: implement
    }
}
