import Blockchain
import Foundation
import Utils

public enum TelemetryHandlers {
    public static let handlers: [any RPCHandler.Type] = [
        Name.self,
        PeersCount.self,
        NetworkKey.self,
    ]

    public static func getHandlers(source: TelemetryDataSource) -> [any RPCHandler] {
        [
            Name(source: source),
            PeersCount(source: source),
            NetworkKey(source: source),
        ]
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

    public struct PeersCount: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = Int

        public static var method: String { "telemetry_peersCount" }
        public static var summary: String? { "Returns the number of connected peers." }

        private let source: TelemetryDataSource

        init(source: TelemetryDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            try await source.getPeersCount()
        }
    }

    public struct NetworkKey: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = String

        public static var method: String { "telemetry_networkKey" }
        public static var summary: String? { "Returns the Ed25519 key for p2p networks." }

        private let source: TelemetryDataSource

        init(source: TelemetryDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            // TODO: implement
            nil
        }
    }
}
