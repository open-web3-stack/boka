import Blockchain
import Foundation
import Utils

enum TelemetryHandlers {
    static func getHandlers(source: TelemetryDataSource & ChainDataSource) -> [any RPCHandler] {
        [
            GetUpdate(source: source),
            Name(source: source),
        ]
    }

    struct GetUpdate: RPCHandler {
        var method: String { "telemetry_getUpdate" }
        typealias Request = VoidRequest
        typealias Response = [String: String]

        private let source: TelemetryDataSource & ChainDataSource

        init(source: TelemetryDataSource & ChainDataSource) {
            self.source = source
        }

        func handle(request _: Request) async throws -> Response? {
            let block = try await source.getBestBlock()
            let peerCount = try await source.getPeersCount()
            return try await [
                "name": source.name(),
                "chainHead": block.header.timeslot.description,
                "blockHash": block.hash.description,
                "peerCount": peerCount.description,
            ]
        }
    }

    struct Name: RPCHandler {
        var method: String { "telemetry_name" }
        typealias Request = VoidRequest
        typealias Response = String

        private let source: TelemetryDataSource

        init(source: TelemetryDataSource) {
            self.source = source
        }

        func handle(request _: Request) async throws -> Response? {
            try await source.name()
        }
    }
}
