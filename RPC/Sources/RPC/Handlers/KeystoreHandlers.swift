import Blockchain
import Codec
import Foundation
import Utils

public enum CreateKeyType: Int32, CaseIterable, Sendable {
    case BLS = 0
    case Bandersnatch = 1
    case Ed25519 = 2
}

public enum KeystoreHandlers {
    public enum Error: Swift.Error {
        case invalidKeyType
    }

    public static let handlers: [any RPCHandler.Type] = [
        CreateKey.self,
        ListKeys.self,
        HasKey.self,
    ]

    public static func getHandlers(source: KeystoreDataSource) -> [any RPCHandler] {
        [
            CreateKey(source: source),
            ListKeys(source: source),
            HasKey(source: source),
        ]
    }

    public struct CreateKey: RPCHandler {
        public typealias Request = Request1<Int32>
        public typealias Response = String

        public static var method: String { "keys_create" }
        public static var requestNames: [String] { ["keyType"] }
        public static var summary: String? { "Create a new key of the specified type and save it to the keystore." }

        private let source: KeystoreDataSource

        init(source: KeystoreDataSource) {
            self.source = source
        }

        public func handle(request: Request) async throws -> Response? {
            let keyTypeInt = request.value

            guard let keyType = CreateKeyType(rawValue: keyTypeInt) else {
                throw Error.invalidKeyType
            }

            return try await source.createKey(keyType: keyType)
        }
    }

    public struct ListKeys: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = [String]

        public static var method: String { "keys_list" }
        public static var summary: String? { "List all public keys in the keystore." }

        private let source: KeystoreDataSource

        init(source: KeystoreDataSource) {
            self.source = source
        }

        public func handle(request _: Request) async throws -> Response? {
            try await source.listKeys()
        }
    }

    public struct HasKey: RPCHandler {
        public typealias Request = Request1<Data>
        public typealias Response = Bool

        public static var method: String { "keys_hasKey" }
        public static var requestNames: [String] { ["publicKey"] }
        public static var summary: String? { "Check if a public key exists in the keystore." }

        private let source: KeystoreDataSource

        init(source: KeystoreDataSource) {
            self.source = source
        }

        public func handle(request: Request) async throws -> Response? {
            let publicKey = request.value
            return try await source.hasKey(publicKey: publicKey)
        }
    }
}
