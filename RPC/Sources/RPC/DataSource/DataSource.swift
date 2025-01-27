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
}

public protocol TelemetryDataSource: Sendable {
    func name() async throws -> String
    func getPeersCount() async throws -> Int
    func getNetworkKey() async throws -> String
}

public typealias DataSource = ChainDataSource & SystemDataSource & TelemetryDataSource
