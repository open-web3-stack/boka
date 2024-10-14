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
    case decodingError(Error)
    var errorDescription: String? {
        switch self {
        case let .invalidFormat(message):
            message
        case let .fileReadError(error):
            "File read error: \(error.localizedDescription)"
        case let .decodingError(error):
            "Decoding error: \(error.localizedDescription)"
        }
    }
}

extension Genesis {
    public func load() async throws -> (StateRef, ProtocolConfigRef) {
        switch self {
        case .dev:
            let config = ProtocolConfigRef.dev
            let state = try State.devGenesis(config: config)
            return (StateRef(state), config)
        case let .file(path):
            let genesis = try GenesisFileHandler().readAndValidateGenesis(from: path)
            var config: ProtocolConfig
            let preset = genesis.preset?.lowercased()
            switch preset {
            case "dev", "mainnet":
                config = (preset == "dev" ? ProtocolConfigRef.dev.value : ProtocolConfigRef.mainnet.value)
                if let genesisConfig = genesis.config {
                    config = config.merged(with: genesisConfig)
                }
            default:
                config = genesis.config!
            }
            let state = try State.devGenesis(config: Ref(config))
            return (StateRef(state), Ref(config))
        }
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
        config = try container.decodeIfPresent(ProtocolConfig.self, forKey: .config)
        state = try container.decode(String.self, forKey: .state)
    }

    func missConfigFiled() -> Bool {
        guard let config else {
            return true
        }
        let mirror = Mirror(reflecting: config)
        for child in mirror.children {
            if let value = child.value as? Int, value == 0 {
                return true
            }
            if let value = child.value as? Gas, value.value == 0 {
                return true
            }
        }
        return false
    }
}

// Class to handle Genesis JSON file operations
class GenesisFileHandler {
    private func validateGenesis(_ genesis: GenesisData) throws {
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
            throw GenesisError.invalidFormat("Invalid or missing 'state'") bjnii
        }
        let preset = genesis.preset?.lowercased()
        if preset != nil, !["dev", "mainnet"].contains(preset!) {
            throw GenesisError.invalidFormat("Invalid preset value. Must be 'dev' or 'mainnet'.")
        }
        if preset == nil, genesis.missConfigFiled() {
            throw GenesisError.invalidFormat("Missing 'preset' or 'config' field.")
        }
    }

    func readAndValidateGenesis(from filePath: String) throws -> GenesisData {
        do {
            let fileContents = try String(contentsOfFile: filePath, encoding: .utf8)
            let data = fileContents.data(using: .utf8)!
            let decoder = JSONDecoder()
            let genesis = try decoder.decode(GenesisData.self, from: data)
            try validateGenesis(genesis)
            return genesis
        } catch let error as GenesisError {
            throw error
        } catch {
            throw GenesisError.fileReadError(error)
        }
    }
}
