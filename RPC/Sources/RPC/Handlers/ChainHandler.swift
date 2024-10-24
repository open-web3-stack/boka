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
            return block
        } else {
            let block = try await source.getBestBlock()
            return block
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
            return [
                "stateRoot": state?.stateRoot.description,
                "blockHash": hash.description,
            ]
        } else {
            // return best block state by default
            let block = try await source.getBestBlock()
            let state = try await source.getState(hash: block.hash)
            return [
                "stateRoot": state?.stateRoot.description,
                "blockHash": block.hash.description,
            ]
        }
    }
}
