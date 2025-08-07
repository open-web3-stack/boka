import Blockchain
import Codec
import Foundation
import Utils

public struct ChainSpec: Codable, Equatable {
    public var id: String
    public var bootnodes: [String]?
    public var genesisHeader: Data
    public var genesisState: [String: Data]
    public var protocolParameters: Data

    private enum CodingKeys: String, CodingKey {
        case id
        case bootnodes
        case genesisHeader = "genesis_header"
        case genesisState = "genesis_state"
        case protocolParameters = "protocol_parameters"
    }

    public init(
        id: String,
        bootnodes: [String]? = nil,
        genesisHeader: Data,
        genesisState: [String: Data],
        protocolParameters: Data
    ) {
        self.id = id
        self.bootnodes = bootnodes
        self.genesisHeader = genesisHeader
        self.genesisState = genesisState
        self.protocolParameters = protocolParameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        bootnodes = try container.decodeIfPresent([String].self, forKey: .bootnodes)
        genesisHeader = try container.decode(Data.self, forKey: .genesisHeader)
        genesisState = try container.decode(Dictionary<String, Data>.self, forKey: .genesisState)
        protocolParameters = try container.decode(Data.self, forKey: .protocolParameters)

        try decoder.setConfig(getConfig())
    }

    public func getConfig() throws -> ProtocolConfigRef {
        let config = try ProtocolConfig.decode(protocolParameters: protocolParameters)
        return Ref(config)
    }

    public func getBlock() throws -> BlockRef {
        let config = try getConfig()
        let header = try JamDecoder.decode(Header.self, from: genesisHeader, withConfig: config)
        return BlockRef(Block(header: header, extrinsic: .dummy(config: config)))
    }

    public func getState() throws -> [Data31: Data] {
        var output: [Data31: Data] = [:]
        for (key, value) in genesisState {
            guard let dataKey = Data31(fromHexString: key) else {
                throw GenesisError.invalidFormat("Invalid genesisState key format: \(key) (not valid hex)")
            }
            output[dataKey] = value
        }
        return output
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .hex
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.userInfo[.config] = try getConfig()
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> ChainSpec {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .hex
        let ref: ConfigRef<ProtocolConfigRef> = .init()
        decoder.userInfo[.config] = ref
        let chainspec = try decoder.decode(ChainSpec.self, from: data)
        try chainspec.validate()
        return chainspec
    }

    private func validate() throws {
        if id.isEmpty {
            throw GenesisError.invalidFormat("Missing 'id'")
        }

        for key in genesisState.keys {
            guard key.count == 62 else {
                throw GenesisError.invalidFormat("Invalid genesisState key length: \(key) (expected 62 characters)")
            }
            guard Data(fromHexString: key) != nil else {
                throw GenesisError.invalidFormat("Invalid genesisState key format: \(key) (not valid hex)")
            }
        }

        if let bootnodes {
            for bootnode in bootnodes {
                try validateBootnodeFormat(bootnode)
            }
        }
    }

    private func validateBootnodeFormat(_ bootnode: String) throws {
        // Format: <name>@<ip>:<port>
        // <name> is 53-character DNS name starting with 'e' followed by base-32 encoded Ed25519 public key
        let components = bootnode.split(separator: "@")
        guard components.count == 2 else {
            throw GenesisError.invalidFormat("Invalid bootnode format: \(bootnode) (expected name@ip:port)")
        }

        let name = String(components[0])
        let addressPort = String(components[1])

        // Validate name: 53 characters, starts with 'e'
        guard name.count == 53, name.hasPrefix("e") else {
            throw GenesisError.invalidFormat("Invalid bootnode name: \(name) (expected 53 characters starting with 'e')")
        }

        // Validate base-32 encoding (check for allowed characters)
        let base32Alphabet = "abcdefghijklmnopqrstuvwxyz234567"
        let nameWithoutPrefix = String(name.dropFirst())
        guard nameWithoutPrefix.allSatisfy({ base32Alphabet.contains($0) }) else {
            throw GenesisError.invalidFormat("Invalid bootnode name encoding: \(name) (not valid base-32)")
        }

        // Validate ip:port format
        let addressComponents = addressPort.split(separator: ":")
        guard addressComponents.count == 2 else {
            throw GenesisError.invalidFormat("Invalid bootnode address: \(addressPort) (expected ip:port)")
        }

        // Validate IP address format
        guard String(addressComponents[0]).isIpAddress() else {
            throw GenesisError.invalidFormat("Invalid bootnode IP address: \(addressComponents[0]) (not a valid IP address)")
        }

        // Validate port is a number
        guard Int(addressComponents[1]) != nil else {
            throw GenesisError.invalidFormat("Invalid bootnode port: \(addressComponents[1]) (not a number)")
        }
    }
}

extension String {
    func isIPv4() -> Bool {
        var sin = sockaddr_in()
        return withCString { cstring in inet_pton(AF_INET, cstring, &sin.sin_addr) } == 1
    }

    func isIPv6() -> Bool {
        var sin6 = sockaddr_in6()
        return withCString { cstring in inet_pton(AF_INET6, cstring, &sin6.sin6_addr) } == 1
    }

    func isIpAddress() -> Bool { isIPv6() || isIPv4() }
}
