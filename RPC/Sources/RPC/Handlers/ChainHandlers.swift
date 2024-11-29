import Blockchain
import Foundation
import Utils

public enum ChainHandlers {
    public static let handlers: [any RPCHandler.Type] = [
        GetBlock.self,
    ]

    public static func getHandlers(source: ChainDataSource) -> [any RPCHandler] {
        [
            GetBlock(source: source),
        ]
    }

    public struct GetBlock: RPCHandler {
        public typealias Request = Request1<Data32?>
        public typealias Response = BlockRef?
        public typealias DataSource = ChainDataSource

        public static var method: String { "chain_getBlock" }
        public static var summary: String? { "Get block by hash. If hash is not provided, returns the best block." }

        private let source: ChainDataSource

        init(source: ChainDataSource) {
            self.source = source
        }

        public func handle(request: Request) async throws -> Response? {
            if let hash = request.value {
                try await source.getBlock(hash: hash)
            } else {
                try await source.getBestBlock()
            }
        }
    }
}
