import Blockchain
import Codec
import Foundation
import Utils

public enum ChainHandlers {
    public static let handlers: [any RPCHandler.Type] = [
        GetBlock.self,
        GetBlockHash.self,
        GetFinalizedHead.self,
        GetHeader.self,
    ]

    public static func getHandlers(source: ChainDataSource) -> [any RPCHandler] {
        [
            GetBlock(source: source),
            GetBlockHash(source: source),
            GetFinalizedHead(source: source),
            GetHeader(source: source),
        ]
    }

    public struct GetBlock: RPCHandler {
        public typealias Request = Request1<Data32?>
        public typealias Response = Data?

        public static var method: String { "chain_getBlock" }
        public static var requestNames: [String] { ["hash"] }
        public static var summary: String? { "Get block by hash. If hash is not provided, returns the best block." }

        private let source: ChainDataSource

        init(source: ChainDataSource) {
            self.source = source
        }

        public func handle(request: Request) async throws -> Response? {
            let block = if let hash = request.value {
                try await source.getBlock(hash: hash)
            } else {
                try await source.getBestBlock()
            }
            return try block.map { try JamEncoder.encode($0) }
        }
    }

    public struct GetBlockHash: RPCHandler {
        public typealias Request = Request1<TimeslotIndex?>
        public typealias Response = Data?

        public static var method: String { "chain_getBlockHash" }
        public static var requestNames: [String] { ["timeslot"] }
        public static var summary: String? { "Get the block hash by timeslot. If timeslot is not provided, returns the best block hash." }

        private let source: ChainDataSource

        init(source: ChainDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            // TODO: implement
            nil
        }
    }

    public struct GetFinalizedHead: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = Data32?

        public static var method: String { "chain_getFinalizedHead" }
        public static var summary: String? { "Get hash of the last finalized block in the canon chain." }

        private let source: ChainDataSource

        init(source: ChainDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            // TODO: implement
            nil
        }
    }

    public struct GetHeader: RPCHandler {
        public typealias Request = Request1<Data32?>
        public typealias Response = Data?

        public static var method: String { "chain_getHeader" }
        public static var requestNames: [String] { ["hash"] }
        public static var summary: String? { "Get block header by hash. If hash is not provided, returns the best block header." }

        private let source: ChainDataSource

        init(source: ChainDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            // TODO: implement
            nil
        }
    }
}
