import Codec
import Foundation
import Utils

public enum StateBackendError: Error {
    case missingState
    case invalidData
}

public final class StateBackend: Sendable {
    private let impl: StateBackendProtocol
    private let config: ProtocolConfigRef
    public let rootHash: Data32

    public init(_ impl: StateBackendProtocol, config: ProtocolConfigRef, rootHash: Data32) {
        self.impl = impl
        self.config = config
        self.rootHash = rootHash
    }

    public func read<Key: StateKey>(_ key: Key) async throws -> Key.Value.ValueType {
        let encodedKey = key.encode().data
        if let ret = try await impl.read(key: encodedKey) {
            guard let ret = try JamDecoder.decode(key.decodeType(), from: ret, withConfig: config) as? Key.Value.ValueType else {
                throw StateBackendError.invalidData
            }
            return ret
        }
        if Key.Value.optional {
            return Key.Value.DecodeType?.none as! Key.Value.ValueType
        }
        throw StateBackendError.missingState
    }

    func batchRead(_: [any StateKey]) async throws -> [(key: any StateKey, value: Codable & Sendable)] {
        []
    }

    func readAll() async throws -> [Data32: Data] {
        [:]
    }
}
