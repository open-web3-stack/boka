import Blockchain
import Foundation
import Utils

struct TelemetryHandler {
    let source: DataSource

    static func getHandlers(source: DataSource) -> [String: JSONRPCHandler] {
        let handler = TelemetryHandler(source: source)

        return [
            "telemetry_getUpdate": handler.getUpdate,
        ]
    }

    func getUpdate(request _: JSONRequest) async throws -> any Encodable {
        let block = try await source.getBestBlock()
        let peerCount = try await source.getPeersCount()
        return [
            "name": "Boka",
            "chainHead": block.header.timeslot.description,
            "blockHash": block.hash.description,
            "peerCount": peerCount.description,
        ]
    }
}
