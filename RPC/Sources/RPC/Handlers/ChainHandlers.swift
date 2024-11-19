import Blockchain
import Foundation
import Utils

enum ChainHandlers {
    static func getHandlers(source: ChainDataSource) -> [any RPCHandler] {
        [
            GetBlock(source: source),
        ]
    }

    struct GetBlock: RPCHandler {
        var method: String { "chain_getBlock" }
        typealias Request = Data32?
        typealias Response = BlockRef?

        private let source: ChainDataSource

        init(source: ChainDataSource) {
            self.source = source
        }

        func handle(request: Request) async throws -> Response? {
            if let hash = request {
                try await source.getBlock(hash: hash)
            } else {
                try await source.getBestBlock()
            }
        }
    }
}
