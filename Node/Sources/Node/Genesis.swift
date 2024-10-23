import Blockchain
import Foundation
import Utils

public enum GenesisPreset: String, Codable, CaseIterable {
    case minimal
    case dev
    case mainnet

    public var config: ProtocolConfigRef {
        switch self {
        case .minimal:
            ProtocolConfigRef.minimal
        case .dev:
            ProtocolConfigRef.dev
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
    public func load() async throws -> (StateRef, BlockRef, ProtocolConfigRef) {
        switch self {
        case let .preset(preset):
            let config = preset.config
            let (state, block) = try State.devGenesis(config: config)
            return (state, block, config)
        case let .file(path):
            let genesis = try readAndValidateGenesis(from: path)
            var config: ProtocolConfig
            if let preset = genesis.preset {
                config = preset.config.value
                if let genesisConfig = genesis.config {
                    config = config.merged(with: genesisConfig)
                }
            } else {
                // The decoder ensures that genesis.config is non-nil when there is no preset
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

struct GenesisData: Codable {
    var name: String
    var id: String
    var bootnodes: [String]
    var preset: GenesisPreset?
    var config: ProtocolConfig?
    // TODO: check & deal with state
    var state: String

    // ensure one of preset or config is present
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        id = try container.decode(String.self, forKey: .id)
        bootnodes = try container.decode([String].self, forKey: .bootnodes)
        preset = try container.decodeIfPresent(GenesisPreset.self, forKey: .preset)
        if preset == nil {
            config = try container.decode(ProtocolConfig.self, forKey: .config, required: true)
        } else {
            config = try container.decodeIfPresent(ProtocolConfig.self, forKey: .config, required: false)
        }
        state = try container.decode(String.self, forKey: .state)
    }
}
