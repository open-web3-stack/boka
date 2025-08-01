import Blockchain
import Codec
import Foundation
import RPC
import Utils

public final class NodeDataSource: Sendable {
    public let blockchain: Blockchain
    public let chainDataProvider: BlockchainDataProvider
    public let networkManager: NetworkManager
    public let name: String
    public let keystore: KeyStore

    public init(
        blockchain: Blockchain,
        chainDataProvider: BlockchainDataProvider,
        networkManager: NetworkManager,
        keystore: KeyStore,
        name: String?
    ) {
        self.blockchain = blockchain
        self.chainDataProvider = chainDataProvider
        self.networkManager = networkManager
        self.keystore = keystore
        self.name = name ?? "Node-\(UUID().uuidString.prefix(8))"
    }
}

extension NodeDataSource: SystemDataSource {
    public func getProperties() async throws -> JSON {
        // TODO: Get a custom set of properties as a JSON object, defined in the chain spec
        JSON.array([])
    }

    public func getChainName() async throws -> String {
        blockchain.config.value.presetName() ?? ""
    }

    public func getNodeRoles() async throws -> [String] {
        [networkManager.network.peerRole.rawValue]
    }

    public func getVersion() async throws -> String {
        // TODO: From spec or config
        "0.0.1"
    }

    public func getHealth() async throws -> Bool {
        // TODO: Check health status
        true
    }

    public func getImplementation() async throws -> String {
        name
    }
}

extension NodeDataSource: BuilderDataSource {
    public func submitWorkPackage(coreIndex: CoreIndex, workPackage: Data, extrinsics: [Data]) async throws {
        let decoded = try JamDecoder.decode(WorkPackage.self, from: workPackage, withConfig: blockchain.config)
        blockchain.publish(event: RuntimeEvents
            .WorkPackagesSubmitted(
                coreIndex: coreIndex,
                workPackage: decoded.asRef(),
                extrinsics: extrinsics
            ))
    }
}

extension NodeDataSource: KeystoreDataSource {
    public func create(keyType: KeyGenType) async throws -> PubKeyItem {
        let secretKey: any SecretKeyProtocol = switch keyType {
        case .BLS:
            try await keystore.generate(BLS.self)
        case .Bandersnatch:
            try await keystore.generate(Bandersnatch.self)
        case .Ed25519:
            try await keystore.generate(Ed25519.self)
        }
        return PubKeyItem(key: secretKey.publicKey.toHexString(), type: keyType.rawValue)
    }

    public func listKeys() async throws -> [PubKeyItem] {
        let blsPublicKeys = await keystore.getAll(BLS.self).map {
            PubKeyItem(key: $0.publicKey.toHexString(), type: KeyGenType.BLS.rawValue)
        }
        let ed25519PublicKeys = await keystore.getAll(Ed25519.self).map {
            PubKeyItem(key: $0.publicKey.toHexString(), type: KeyGenType.Ed25519.rawValue)
        }
        let bandersnatchPublicKeys = await keystore.getAll(Bandersnatch.self).map {
            PubKeyItem(key: $0.publicKey.toHexString(), type: KeyGenType.Bandersnatch.rawValue)
        }
        return blsPublicKeys + ed25519PublicKeys + bandersnatchPublicKeys
    }

    public func has(keyType: KeyGenType, with publicKey: Data) async throws -> Bool {
        switch keyType {
        case .BLS:
            if let publicKeyData = Data144(publicKey) {
                if let publicKey = try? BLS.PublicKey(data: publicKeyData) {
                    return await keystore.contains(publicKey: publicKey)
                }
            }
        case .Ed25519:
            if let publicKeyData = Data32(publicKey) {
                if let publicKey = try? Ed25519.PublicKey(from: publicKeyData) {
                    return await keystore.contains(publicKey: publicKey)
                }
            }
        case .Bandersnatch:
            if let publicKeyData = Data32(publicKey) {
                if let publicKey = try? Bandersnatch.PublicKey(data: publicKeyData) {
                    return await keystore.contains(publicKey: publicKey)
                }
            }
        }
        return false
    }
}

extension NodeDataSource: ChainDataSource {
    public func getKeys(prefix: Data, count: UInt32, startKey: Data31?, blockHash: Data32?) async throws -> [String] {
        try await chainDataProvider.getKeys(prefix: prefix, count: count, startKey: startKey, blockHash: blockHash)
    }

    public func getStorage(key: Data31, blockHash: Utils.Data32?) async throws -> [String] {
        try await chainDataProvider.getStorage(key: key, blockHash: blockHash)
    }

    public func getBestBlock() async throws -> BlockRef {
        try await chainDataProvider.getBlock(hash: chainDataProvider.bestHead.hash)
    }

    public func getBlock(hash: Data32) async throws -> BlockRef? {
        try await chainDataProvider.getBlock(hash: hash)
    }

    public func getState(blockHash: Data32, key: Data31) async throws -> Data? {
        let state = try await chainDataProvider.getState(hash: blockHash)
        return try await state.value.read(key: key)
    }

    public func getBlockHash(byTimeslot timeslot: TimeslotIndex) async throws -> Set<Data32> {
        try await chainDataProvider.getBlockHash(byTimeslot: timeslot)
    }

    public func getHeader(hash: Data32) async throws -> HeaderRef? {
        try await chainDataProvider.getHeader(hash: hash)
    }

    public func getFinalizedHead() async throws -> Data32? {
        try await chainDataProvider.getFinalizedHead()
    }
}

extension NodeDataSource: TelemetryDataSource {
    public func name() async throws -> String {
        name
    }

    public func getPeersCount() async throws -> Int {
        networkManager.peersCount
    }

    public func getNetworkKey() async throws -> String {
        networkManager.network.networkKey
    }
}
