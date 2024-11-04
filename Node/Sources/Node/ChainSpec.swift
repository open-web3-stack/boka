import Blockchain
import Codec
import Foundation
import Utils

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

private func mergeConfig(preset: GenesisPreset?, config: ProtocolConfig?) throws -> ProtocolConfigRef {
    if let preset {
        let ret = preset.config.value
        if let genesisConfig = config {
            return Ref(ret.merged(with: genesisConfig))
        }
        return Ref(ret)
    }
    if let config {
        return Ref(config)
    }
    throw GenesisError.invalidFormat("One of 'preset' or 'config' is required")
}

public struct ChainSpec: Codable, Equatable {
    public var name: String
    public var id: String
    public var bootnodes: [String]
    public var preset: GenesisPreset?
    public var config: ProtocolConfig?
    public var block: Block
    public var state: [Data32: Data]

    public init(
        name: String,
        id: String,
        bootnodes: [String],
        preset: GenesisPreset?,
        config: ProtocolConfig?,
        block: Block,
        state: [Data32: Data]
    ) {
        self.name = name
        self.id = id
        self.bootnodes = bootnodes
        self.preset = preset
        self.config = config
        self.block = block
        self.state = state
    }

    public init(from decoder: Decoder) throws {
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

        try decoder.setConfig(mergeConfig(preset: preset, config: config))

        block = try container.decode(Block.self, forKey: .block)
        state = try container.decode([Data32: Data].self, forKey: .state)
    }

    public func getConfig() throws -> ProtocolConfigRef {
        try mergeConfig(preset: preset, config: config)
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .hex
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.userInfo[.config] = try getConfig()
        return try encoder.encode(self)
    }

    public func encodeBinary() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .hex
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.userInfo[.config] = try getConfig()
        let binary = try ChainSpecBinary(
            name: name,
            id: id,
            bootnodes: bootnodes,
            preset: preset,
            config: config,
            block: JamEncoder.encode(block),
            state: JamEncoder.encode(state)
        )
        return try encoder.encode(binary)
    }

    public static func decode(from data: Data) throws -> ChainSpec {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .hex
        let ref: ConfigRef<ProtocolConfigRef> = .init()
        decoder.userInfo[.config] = ref
        if let chainspec = try? decoder.decode(ChainSpec.self, from: data) {
            try chainspec.validate()
            return chainspec
        }
        let binary = try decoder.decode(ChainSpecBinary.self, from: data)
        let chainspec = try binary.toChainSpec()
        try chainspec.validate()
        return chainspec
    }

    private func validate() throws {
        // Validate required fields
        if name.isEmpty {
            throw GenesisError.invalidFormat("Missing 'name'")
        }
        if id.isEmpty {
            throw GenesisError.invalidFormat("Missing 'id'")
        }
        if preset == nil, config == nil {
            throw GenesisError.invalidFormat("One of 'preset' or 'config' is required")
        }
    }
}

public struct ChainSpecBinary: Codable {
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

    public func toChainSpec() throws -> ChainSpec {
        let finalConfig = try mergeConfig(preset: preset, config: config)
        let block = try JamDecoder(data: block, config: finalConfig).decode(Block.self)
        let state = try JamDecoder(data: state, config: finalConfig).decode([Data32: Data].self)
        return ChainSpec(
            name: name,
            id: id,
            bootnodes: bootnodes,
            preset: preset,
            config: config,
            block: block,
            state: state
        )
    }

    public init(from decoder: Decoder) throws {
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

        block = try container.decode(Data.self, forKey: .block)
        state = try container.decode(Data.self, forKey: .state)
    }
}
