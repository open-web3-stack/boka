import Blockchain
import Codec
import Foundation
import Utils

public enum GenesisPreset: String, Codable, CaseIterable {
    case minimal
    case dev
    case tiny
    case mainnet

    public var config: ProtocolConfigRef {
        switch self {
        case .minimal:
            ProtocolConfigRef.minimal
        case .dev:
            ProtocolConfigRef.dev
        case .tiny:
            ProtocolConfigRef.tiny
        case .mainnet:
            ProtocolConfigRef.mainnet
        }
    }
}

public enum Genesis {
    case preset(GenesisPreset)
    case file(path: String)
}

public enum GenesisError: Error {
    case invalidFormat(String)
    case fileReadError(Error)
    var errorDescription: String? {
        switch self {
        case let .invalidFormat(message):
            message
        case let .fileReadError(error):
            "File read error: \(error.localizedDescription)"
        }
    }
}

extension Genesis {
    public func load() async throws -> ChainSpec {
        switch self {
        case let .preset(preset):
            let config = preset.config
            let (state, block) = try State.devGenesis(config: config)
            var kv: [String: Data] = [:]
            for (key, value) in state.value.layer.toKV() {
                if let value {
                    kv[key.toHexString()] = try JamEncoder.encode(value)
                }
            }
            return try ChainSpec(
                id: preset.rawValue,
                bootnodes: [],
                genesisHeader: JamEncoder.encode(block.value.header),
                genesisState: kv,
                protocolParameters: config.value.encoded
            )
        case let .file(path):
            let data = try readFile(from: path)
            return try ChainSpec.decode(from: data)
        }
    }

    private func readFile(from filePath: String) throws -> Data {
        do {
            let fileContents = try String(contentsOfFile: filePath, encoding: .utf8)
            return Data(fileContents.utf8)
        } catch {
            throw GenesisError.fileReadError(error)
        }
    }
}
