import Blockchain
import Foundation
import Utils

public enum TelemetryHandlers {
    public static let handlers: [any RPCHandler.Type] = [
        GetUpdate.self,
        Name.self,
    ]

    public static func getHandlers(source: TelemetryDataSource & ChainDataSource) -> [any RPCHandler] {
        [
            GetUpdate(source: source),
            Name(source: source),
        ]
    }

    public struct GetUpdate: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = [String: String]

        public static var method: String { "telemetry_getUpdate" }
        public static var summary: String? { "Returns the latest telemetry update." }

        private let source: TelemetryDataSource & ChainDataSource

        init(source: TelemetryDataSource & ChainDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            let block = try await source.getBestBlock()
            let peerCount = try await source.getPeersCount()
            return [
                "chainHead": block.header.timeslot.description,
                "blockHash": block.hash.description,
                "peerCount": peerCount.description,
            ]
        }
    }

    public struct Name: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = String

        public static var method: String { "telemetry_name" }
        public static var summary: String? { "Returns the name of the node." }

        private let source: TelemetryDataSource

        init(source: TelemetryDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            try await source.name()
        }
    }
}
