import Utils

public enum BlockchainDataProviderError: Error {
    case unknownHash
}

public protocol BlockchainDataProvider {
    func hasHeader(hash: Data32) async throws -> Bool
    func isHead(hash: Data32) async throws -> Bool

    func getHeader(hash: Data32) async throws -> HeaderRef
    func getBlock(hash: Data32) async throws -> BlockRef
    func getState(hash: Data32) async throws -> StateRef
    func getFinalizedHead() async throws -> Data32
    func getHeads() async throws -> [Data32]
    func getBlockHash(index: TimeslotIndex) async throws -> [Data32]

    func add(state: StateRef, isHead: Bool) async throws
    func setFinalizedHead(hash: Data32) async throws
    // remove header, block and state
    func remove(hash: Data32) async throws

    // protected method
    func _updateHeadNoCheck(hash: Data32, parent: Data32) async throws
}

extension BlockchainDataProvider {
    public func updateHead(hash: Data32, parent: Data32) async throws {
        try await debugCheck(hasHeader(hash: hash))
        try await debugCheck(hasHeader(hash: parent))

        try await _updateHeadNoCheck(hash: hash, parent: parent)
    }

    public func add(state: StateRef) async throws {
        try await add(state: state, isHead: false)
    }
}
