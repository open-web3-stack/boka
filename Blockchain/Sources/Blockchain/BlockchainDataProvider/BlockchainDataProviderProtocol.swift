import Utils

public protocol BlockchainDataProviderProtocol: Sendable {
//    func hasWorkReport(hash: Data32) async throws -> Bool
    func hasBlock(hash: Data32) async throws -> Bool
    func hasState(hash: Data32) async throws -> Bool
    func isHead(hash: Data32) async throws -> Bool

    func getBlockNumber(hash: Data32) async throws -> UInt32?

    func getHeader(hash: Data32) async throws -> HeaderRef?

//    func getWorkReport(hash: Data32) async throws -> WorkReportRef?

    func getBlock(hash: Data32) async throws -> BlockRef?

    func getState(hash: Data32) async throws -> StateRef?

    func getFinalizedHead() async throws -> Data32?

    func getHeads() async throws -> Set<Data32>

    func getKeys(prefix: Data32, count: UInt32, startKey: Data32?, blockHash: Data32?) async throws -> [String]

    func getStorage(key: Data32, blockHash: Data32?) async throws -> [String]

    /// return empty set if not found
    func getBlockHash(byTimeslot timeslot: TimeslotIndex) async throws -> Set<Data32>
    /// return empty set if not found
    func getBlockHash(byNumber number: UInt32) async throws -> Set<Data32>

//    func addWorkReport(workReport: WorkReportRef) async throws
    func add(block: BlockRef) async throws
    func add(state: StateRef) async throws
    func setFinalizedHead(hash: Data32) async throws

    /// throw BlockchainDataProviderError.noData if parent is not a head
    func updateHead(hash: Data32, parent: Data32) async throws

    /// remove header, block, workReport, state
    func remove(hash: Data32) async throws

    var genesisBlockHash: Data32 { get }
}
