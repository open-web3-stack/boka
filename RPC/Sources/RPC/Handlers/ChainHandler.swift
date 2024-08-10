import Blockchain
import Foundation
import Utils

struct ChainHandler {
    let source: DataSource

    static func getHandlers(source: DataSource) -> [String: JSONRPCHandler] {
        let handler = ChainHandler(source: source)

        return [
            "chain_getBlock": handler.getBlock,
        ]
    }

    func getBlock(request: JSONRequest) async throws -> any Encodable {
        let hash = request.params?["hash"] as? String
        if let hash {
            guard let data = Data(fromHexString: hash), let data32 = Data32(data) else {
                throw JSONError(code: -32602, message: "Invalid block hash")
            }
            let block = try await source.getBlock(hash: data32)
            return block.map { ["hash": $0.hash.description, "parentHash": $0.header.parentHash.description] }
        } else {
            let block = try await source.getBestBlock()
            return ["hash": block.hash.description, "parentHash": block.header.parentHash.description]
        }
    }
}
