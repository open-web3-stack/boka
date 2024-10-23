import Blockchain
import Foundation
import Utils

struct ChainHandler {
    let source: DataSource

    static func getHandlers(source: DataSource) -> [String: JSONRPCHandler] {
        let handler = ChainHandler(source: source)

        return [
            "chain_getBlock": handler.getBlock,
            "chain_getState": handler.getState,
        ]
    }

    func getBlock(request: JSONRequest) async throws -> any Encodable {
        let hash = request.params?["hash"] as? String
        if let hash {
            guard let data = Data(fromHexString: hash), let data32 = Data32(data) else {
                throw JSONError(code: -32602, message: "Invalid block hash")
            }
            let block = try await source.getBlock(hash: data32)
            return block.map { [
                "hash": $0.hash.description,
                "parentHash": $0.header.parentHash.description,
            ] }
        } else {
            let block = try await source.getBestBlock()
            return [
                "hash": block.hash.description,
                "parentHash": block.header.parentHash.description,
            ]
        }
    }

    func getState(request: JSONRequest) async throws -> any Encodable {
        let hash = request.params?["hash"] as? String
        if let hash {
            guard let data = Data(fromHexString: hash), let data32 = Data32(data) else {
                throw JSONError(code: -32602, message: "Invalid block hash")
            }
            let state = try await source.getState(hash: data32)
            // return state root for now
            return state?.stateRoot.description
        } else {
            // return best block state by default
            let block = try await source.getBestBlock()
            let state = try await source.getState(hash: block.hash)
            return state?.stateRoot.description
        }
    }
}
