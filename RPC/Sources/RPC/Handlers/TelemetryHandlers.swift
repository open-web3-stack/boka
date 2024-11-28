import Blockchain
import Foundation
import Utils

enum TelemetryHandlers {
    static let handlers: [any RPCHandler.Type] = [
        GetUpdate.self,
        Name.self,
    ]

    static func getHandlers(source: TelemetryDataSource & ChainDataSource) -> [any RPCHandler] {
        [
            GetUpdate(source: source),
            Name(source: source),
        ]
    }

    struct GetUpdate: RPCHandler {
        typealias Request = VoidRequest
        typealias Response = [String: String]

        static var method: String { "telemetry_getUpdate" }

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
        typealias Request = VoidRequest
        typealias Response = String

        static var method: String { "telemetry_name" }

        private let source: TelemetryDataSource

        init(source: TelemetryDataSource) {
            self.source = source
        }

        func handle(request _: Request) async throws -> Response? {
            try await source.name()
        }
    }
}
