import Blockchain
import Foundation
import Utils

public protocol SystemDataSource: Sendable {
    func getNodeRoles() async throws -> [String]
    func getVersion() async throws -> String
    func getHealth() async throws -> Bool
    func getImplementation() async throws -> String
    func getProperties() async throws -> JSON
    func getChainName() async throws -> String
}

public protocol ChainDataSource: Sendable {
    func getBestBlock() async throws -> BlockRef
    func getBlock(hash: Data32) async throws -> BlockRef?
    func getState(blockHash: Data32, key: Data32) async throws -> Data?
    func getBlockHash(byTimeslot timeslot: TimeslotIndex) async throws -> Set<Data32>
    func getHeader(hash: Data32) async throws -> HeaderRef?
    func getFinalizedHead() async throws -> Data32?
    func getKeys(prefix: Data32, count: UInt32, startKey: Data32?, blockHash: Data32?) async throws -> [String]
    func getStorage(key: Data32, blockHash: Data32?) async throws -> [String]
}

public protocol BuilderDataSource: Sendable {
    func submitWorkPackage(coreIndex: CoreIndex, workPackage: Data, extrinsics: [Data]) async throws
}

public protocol TelemetryDataSource: Sendable {
    func name() async throws -> String
    func getPeersCount() async throws -> Int
    func getNetworkKey() async throws -> String
}

public protocol KeystoreDataSource: Sendable {
    func create(keyType: CreateKeyType) async throws -> String
    func listKeys() async throws -> [PubKeyItem]
    func hasKey(publicKey: Data) async throws -> Bool
}

public typealias DataSource = BuilderDataSource & ChainDataSource & KeystoreDataSource & SystemDataSource & TelemetryDataSource
