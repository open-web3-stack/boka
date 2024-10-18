import Blockchain
import Foundation
import Utils

public enum Genesis {
    case dev
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
    public func load() async throws -> (StateRef, BlockRef, ProtocolConfigRef) {
        switch self {
        case .dev:
            let config = ProtocolConfigRef.dev
            let (state, block) = try State.devGenesis(config: config)
            return (state, block, config)
        case let .file(path):
            let genesis = try readAndValidateGenesis(from: path)
            var config: ProtocolConfig
            let preset = genesis.preset?.lowercased()
            switch preset {
            case "dev", "mainnet":
                config =
                    (preset == "dev"
                        ? ProtocolConfigRef.dev.value : ProtocolConfigRef.mainnet.value)
                if let genesisConfig = genesis.config {
                    config = config.merged(with: genesisConfig)
                }
            default:
                // In this case, genesis.config has been verified to be non-nil
                config = genesis.config!
            }
            let configRef = Ref(config)
            let (state, block) = try State.devGenesis(config: configRef)
            return (state, block, configRef)
        }
    }

    private func validate(_ genesis: GenesisData) throws {
        // Validate required fields
        if genesis.name.isEmpty {
            throw GenesisError.invalidFormat("Invalid or missing 'name'")
        }
        if genesis.id.isEmpty {
            throw GenesisError.invalidFormat("Invalid or missing 'id'")
        }
        if genesis.bootnodes.isEmpty {
            throw GenesisError.invalidFormat("Invalid or missing 'bootnodes'")
        }
        if genesis.state.isEmpty {
            throw GenesisError.invalidFormat("Invalid or missing 'state'")
        }
        let preset = genesis.preset?.lowercased()
        if preset != nil, !["dev", "mainnet"].contains(preset!) {
            throw GenesisError.invalidFormat("Invalid preset value. Must be 'dev' or 'mainnet'.")
        }
    }

    func readAndValidateGenesis(from filePath: String) throws -> GenesisData {
        do {
            let fileContents = try String(contentsOfFile: filePath, encoding: .utf8)
            let data = fileContents.data(using: .utf8)!
            let decoder = JSONDecoder()
            let genesis = try decoder.decode(GenesisData.self, from: data)
            try validate(genesis)
            return genesis
        } catch let error as GenesisError {
            throw error
        } catch {
            throw GenesisError.fileReadError(error)
        }
    }
}

extension KeyedDecodingContainer {
    func decode(_: ProtocolConfig.Type, forKey key: K, required: Bool = true) throws -> ProtocolConfig {
        let nestedDecoder = try superDecoder(forKey: key)
        return try ProtocolConfig(from: nestedDecoder, required)
    }

    func decodeIfPresent(_: ProtocolConfig.Type, forKey key: K, required: Bool = false) throws -> ProtocolConfig? {
        guard contains(key) else { return nil }
        let nestedDecoder = try superDecoder(forKey: key)
        return try ProtocolConfig(from: nestedDecoder, required)
    }
}

struct GenesisData: Sendable, Codable {
    var name: String
    var id: String
    var bootnodes: [String]
    var preset: String?
    var config: ProtocolConfig?
    // TODO: check & deal with state
    var state: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        id = try container.decode(String.self, forKey: .id)
        bootnodes = try container.decode([String].self, forKey: .bootnodes)
        preset = try container.decodeIfPresent(String.self, forKey: .preset)
        if preset == nil || !["dev", "mainnet"].contains(preset) {
            config = try container.decode(ProtocolConfig.self, forKey: .config, required: true)
        } else {
            config = try container.decodeIfPresent(ProtocolConfig.self, forKey: .config, required: false)
        }
        state = try container.decode(String.self, forKey: .state)
    }
}
