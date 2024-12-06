import Blockchain
import Foundation
import RocksDBSwift
import Utils

public enum RocksDBBackendError: Error {
    case genesisHashMismatch(expected: Data32, actual: Data)
}

public final class RocksDBBackend {
    private let db: RocksDB<StoreId>
    private let meta: Store<StoreId, NoopCoder>
    private let blocks: Store<StoreId, JamCoder<Data32, BlockRef>>

    public let genesisBlockHash: Data32

    public init(path: URL, config: ProtocolConfigRef, genesisBlockHash: Data32) throws {
        db = try RocksDB(path: path)
        meta = Store(db: db, column: .meta, coder: NoopCoder())
        blocks = Store(db: db, column: .blocks, coder: JamCoder(config: config))

        self.genesisBlockHash = genesisBlockHash

        let genesis = try meta.get(key: MetaKey.genesisHash.key)
        if let genesis {
            guard genesis == genesisBlockHash.data else {
                throw RocksDBBackendError.genesisHashMismatch(expected: genesisBlockHash, actual: genesis)
            }
        } else {
            // must be a new db
            try meta.put(key: MetaKey.genesisHash.key, value: genesisBlockHash.data)
        }
    }
}

extension RocksDBBackend: BlockchainDataProviderProtocol {
    public func hasBlock(hash _: Data32) async throws -> Bool {
        fatalError("unimplemented")
    }

    public func hasState(hash _: Data32) async throws -> Bool {
        fatalError("unimplemented")
    }

    public func isHead(hash _: Data32) async throws -> Bool {
        fatalError("unimplemented")
    }

    public func getBlockNumber(hash _: Data32) async throws -> UInt32 {
        fatalError("unimplemented")
    }

    public func getHeader(hash _: Data32) async throws -> HeaderRef {
        fatalError("unimplemented")
    }

    public func getBlock(hash _: Data32) async throws -> BlockRef {
        fatalError("unimplemented")
    }

    public func getState(hash _: Data32) async throws -> StateRef {
        fatalError("unimplemented")
    }

    public func getFinalizedHead() async throws -> Data32 {
        fatalError("unimplemented")
    }

    public func getHeads() async throws -> Set<Data32> {
        fatalError("unimplemented")
    }

    public func getBlockHash(byTimeslot _: TimeslotIndex) async throws -> Set<Data32> {
        fatalError("unimplemented")
    }

    public func getBlockHash(byNumber _: UInt32) async throws -> Set<Data32> {
        fatalError("unimplemented")
    }

    public func add(block _: BlockRef) async throws {
        fatalError("unimplemented")
    }

    public func add(state _: StateRef) async throws {
        fatalError("unimplemented")
    }

    public func setFinalizedHead(hash _: Data32) async throws {
        fatalError("unimplemented")
    }

    public func updateHead(hash _: Data32, parent _: Data32) async throws {
        fatalError("unimplemented")
    }

    public func remove(hash _: Data32) async throws {
        fatalError("unimplemented")
    }
}

extension RocksDBBackend: StateBackendProtocol {
    public func read(key _: Data) async throws -> Data? {
        fatalError("unimplemented")
    }

    public func readAll(prefix _: Data, startKey _: Data?, limit _: UInt32?) async throws -> [(key: Data, value: Data)] {
        fatalError("unimplemented")
    }

    public func batchUpdate(_: [StateBackendOperation]) async throws {
        fatalError("unimplemented")
    }

    public func readValue(hash _: Data32) async throws -> Data? {
        fatalError("unimplemented")
    }

    public func gc(callback _: @Sendable (Data) -> Data32?) async throws {
        fatalError("unimplemented")
    }
}
