import Blockchain
import Codec
import Foundation
import Utils

public enum CreateKeyType: String, CaseIterable, Sendable {
    case BLS = "bls"
    case Bandersnatch = "bandersnatch"
    case Ed25519 = "ed25519"

    static func from(data: Data) -> CreateKeyType? {
        if let string = String(data: data, encoding: .utf8) {
            return CreateKeyType(rawValue: string)
        }
        return nil
    }
}

public struct PubKeyItem: Sendable, Codable {
    public let key: String
    public let type: String

    public init(key: String, type: String) {
        self.key = key
        self.type = type
    }
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
        public typealias Request = Request1<Data>
        public typealias Response = String

        public static var method: String { "keys_create" }
        public static var requestNames: [String] { ["keyType"] }
        public static var summary: String? { "Create a new key of the specified type and save it to the keystore." }

        private let source: KeystoreDataSource

        init(source: KeystoreDataSource) {
            self.source = source
        }

        public func handle(request: Request) async throws -> Response? {
            guard let keyType = CreateKeyType.from(data: request.value) else {
                throw Error.invalidKeyType
            }

            return try await source.create(keyType: keyType)
        }
    }

    public struct ListKeys: RPCHandler {
        public typealias Request = VoidRequest
        public typealias Response = [PubKeyItem]

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
        public typealias Request = Request2<String, Data>
        public typealias Response = Bool

        public static var method: String { "keys_hasKey" }
        public static var requestNames: [String] { ["keyType", "publicKey"] }
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
