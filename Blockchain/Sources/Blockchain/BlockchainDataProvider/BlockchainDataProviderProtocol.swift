import Utils

public enum BlockchainDataProviderError: Error, Equatable {
    case noData(hash: Data32)
}

public protocol BlockchainDataProviderProtocol: Sendable {
    func hasBlock(hash: Data32) async throws -> Bool
    func hasState(hash: Data32) async throws -> Bool
    func isHead(hash: Data32) async throws -> Bool

    /// throw BlockchainDataProviderError.noData if not found
    func getHeader(hash: Data32) async throws -> HeaderRef

    /// throw BlockchainDataProviderError.noData if not found
    func getBlock(hash: Data32) async throws -> BlockRef

    /// throw BlockchainDataProviderError.noData if not found
    func getState(hash: Data32) async throws -> StateRef

    /// throw BlockchainDataProviderError.noData if not found
    func getFinalizedHead() async throws -> Data32
    func getHeads() async throws -> Set<Data32>

    /// return empty set if not found
    func getBlockHash(byTimeslot timeslot: TimeslotIndex) async throws -> Set<Data32>

    func add(block: BlockRef) async throws
    func add(state: StateRef) async throws
    func setFinalizedHead(hash: Data32) async throws

    /// throw BlockchainDataProviderError.noData if parent is not a head
    func updateHead(hash: Data32, parent: Data32) async throws

    /// remove header, block and state
    func remove(hash: Data32) async throws
}
