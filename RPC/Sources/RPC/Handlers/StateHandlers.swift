import Blockchain
import Foundation
import Utils

public enum StateHandlers {
    public static let handlers: [any RPCHandler.Type] = [
        GetKeys.self,
        GetStorage.self,
    ]

    public static func getHandlers(source: ChainDataSource) -> [any RPCHandler] {
        [
            GetKeys(source: source),
            GetStorage(source: source),
        ]
    }

    public struct GetKeys: RPCHandler {
        public typealias Request = Request4<Data, UInt32, Data31?, Data32?>
        public typealias Response = [String]

        public static var method: String {
            "state_getKeys"
        }

        public static var requestNames: [String] {
            ["prefix", "count", "startKey", "blockHash"]
        }

        public static var summary: String? {
            "Returns the keys of the state."
        }

        private let source: ChainDataSource

        init(source: ChainDataSource) {
            self.source = source
        }

        public func handle(request: Request) async throws -> Response? {
            try await source.getKeys(prefix: request.value.0, count: request.value.1, startKey: request.value.2, blockHash: request.value.3)
        }
    }

    public struct GetStorage: RPCHandler {
        public typealias Request = Request2<Data31, Data32?>
        public typealias Response = [String]

        public static var method: String {
            "state_getStorage"
        }

        public static var requestNames: [String] {
            ["key", "blockHash"]
        }

        public static var summary: String? {
            "Returns the storage entry for a key for blockHash or best head."
        }

        private let source: ChainDataSource

        init(source: ChainDataSource) {
            self.source = source
        }

        public func handle(request: Request) async throws -> Response? {
            try await source.getStorage(key: request.value.0, blockHash: request.value.1)
        }
    }
}
