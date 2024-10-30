import Blockchain
import Codec
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
            let state = genesis.state.asRef()
            let block = genesis.block.asRef()

            return (state, block, configRef)
        }
    }

    private func validate(_ genesis: GenesisData) throws {
        // Validate required fields
        if genesis.name.isEmpty {
            throw GenesisError.invalidFormat("Missing 'name'")
        }
        if genesis.id.isEmpty {
            throw GenesisError.invalidFormat("Missing 'id'")
        }
        if genesis.preset == nil, genesis.config == nil {
            throw GenesisError.invalidFormat("One of 'preset' or 'config' is required")
        }
    }

    private func readFile(from filePath: String) throws -> Data {
        do {
            let fileContents = try String(contentsOfFile: filePath, encoding: .utf8)
            return fileContents.data(using: .utf8)!
        } catch {
            throw GenesisError.fileReadError(error)
        }
    }

    private func parseGenesis(from data: Data) throws -> GenesisData {
        let decoder = JSONDecoder()
        if let genesisData = try? decoder.decode(GenesisData.self, from: data) {
            return genesisData
        }
        let genesisData = try decoder.decode(GenesisDataBinary.self, from: data)
        return try genesisData.toGenesisData()
    }

    func readAndValidateGenesis(from filePath: String) throws -> GenesisData {
        let data = try readFile(from: filePath)
        let genesis = try parseGenesis(from: data)
        try validate(genesis)
        return genesis
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

private func getConfig(preset: GenesisPreset?, config: ProtocolConfig?) throws -> ProtocolConfig {
    if let preset {
        let ret = preset.config.value
        if let genesisConfig = config {
            return ret.merged(with: genesisConfig)
        }
        return ret
    }
    if let config {
        return config
    }
    throw GenesisError.invalidFormat("One of 'preset' or 'config' is required")
}

public struct GenesisData: Codable {
    public var name: String
    public var id: String
    public var bootnodes: [String]
    public var preset: GenesisPreset?
    public var config: ProtocolConfig?
    public var block: Block
    public var state: State

    public init(
        name: String,
        id: String,
        bootnodes: [String],
        preset: GenesisPreset?,
        config: ProtocolConfig?,
        block: Block,
        state: State
    ) {
        self.name = name
        self.id = id
        self.bootnodes = bootnodes
        self.preset = preset
        self.config = config
        self.block = block
        self.state = state
    }
}

public struct GenesisDataBinary: Codable {
    public var name: String
    public var id: String
    public var bootnodes: [String]
    public var preset: GenesisPreset?
    public var config: ProtocolConfig?
    public var block: Data
    public var state: Data

    public init(
        name: String,
        id: String,
        bootnodes: [String],
        preset: GenesisPreset?,
        config: ProtocolConfig?,
        block: Data,
        state: Data
    ) {
        self.name = name
        self.id = id
        self.bootnodes = bootnodes
        self.preset = preset
        self.config = config
        self.block = block
        self.state = state
    }

    public func toGenesisData() throws -> GenesisData {
        let block = try JamDecoder(data: block, config: config).decode(Block.self)
        let state = try JamDecoder(data: state, config: config).decode(State.self)
        return GenesisData(
            name: name,
            id: id,
            bootnodes: bootnodes,
            preset: preset,
            config: config,
            block: block,
            state: state
        )
    }
}
