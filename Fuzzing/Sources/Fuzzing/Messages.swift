import Blockchain
import Codec
import Foundation
import Utils

public struct FuzzVersion: Codable {
    public let major: UInt8
    public let minor: UInt8
    public let patch: UInt8

    public init(major: UInt8, minor: UInt8, patch: UInt8) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    private enum CodingKeys: String, CodingKey {
        case major, minor, patch
    }
}

extension FuzzVersion: CustomStringConvertible {
    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}

public struct FuzzPeerInfo: Codable {
    public let name: String
    public let appVersion: FuzzVersion
    public let jamVersion: FuzzVersion

    public init(
        name: String,
        appVersion: FuzzVersion = FuzzVersion(major: 1, minor: 0, patch: 0),
        jamVersion: FuzzVersion = FuzzVersion(major: 0, minor: 6, patch: 6)
    ) {
        self.name = name
        self.appVersion = appVersion
        self.jamVersion = jamVersion
    }
}

public struct FuzzKeyValue: Codable {
    public let key: Data31
    public let value: Data

    public init(key: Data31, value: Data) {
        self.key = key
        self.value = value
    }
}

public typealias FuzzState = [FuzzKeyValue]

public struct FuzzSetState: Codable {
    public let header: Header
    public let state: FuzzState

    public init(header: Header, state: FuzzState) {
        self.header = header
        self.state = state
    }
}

public typealias FuzzGetState = Data32 // HeaderHash
public typealias FuzzStateRoot = Data32 // StateRootHash

public enum FuzzingMessage: Codable {
    case peerInfo(FuzzPeerInfo)
    case importBlock(Block)
    case setState(FuzzSetState)
    case getState(FuzzGetState)
    case state(FuzzState)
    case stateRoot(FuzzStateRoot)

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let variant = try container.decode(UInt8.self)
        switch variant {
        case 0:
            self = try .peerInfo(container.decode(FuzzPeerInfo.self))
        case 1:
            self = try .importBlock(container.decode(Block.self))
        case 2:
            self = try .setState(container.decode(FuzzSetState.self))
        case 3:
            self = try .getState(container.decode(FuzzGetState.self))
        case 4:
            self = try .state(container.decode(FuzzState.self))
        case 5:
            self = try .stateRoot(container.decode(FuzzStateRoot.self))
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid FuzzingMessage variant: \(variant)"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        switch self {
        case let .peerInfo(value):
            try container.encode(UInt8(0))
            try container.encode(value)
        case let .importBlock(value):
            try container.encode(UInt8(1))
            try container.encode(value)
        case let .setState(value):
            try container.encode(UInt8(2))
            try container.encode(value)
        case let .getState(value):
            try container.encode(UInt8(3))
            try container.encode(value)
        case let .state(value):
            try container.encode(UInt8(4))
            try container.encode(value)
        case let .stateRoot(value):
            try container.encode(UInt8(5))
            try container.encode(value)
        }
    }
}
