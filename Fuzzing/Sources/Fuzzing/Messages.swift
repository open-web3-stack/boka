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

public let FEATURE_ANCESTRY: UInt32 = 1
public let FEATURE_FORK: UInt32 = 2

public struct FuzzPeerInfo: Codable {
    public let fuzzVersion: UInt8
    public let fuzzFeatures: UInt32
    public let jamVersion: FuzzVersion
    public let appVersion: FuzzVersion
    public let appName: String

    public init(
        name: String,
        appVersion: FuzzVersion = FuzzVersion(major: 0, minor: 1, patch: 0),
        jamVersion: FuzzVersion = FuzzVersion(major: 0, minor: 7, patch: 2),
        fuzzVersion: UInt8 = 1,
        fuzzFeatures: UInt32 = FEATURE_ANCESTRY | FEATURE_FORK,
    ) {
        appName = name
        self.appVersion = appVersion
        self.jamVersion = jamVersion
        self.fuzzVersion = fuzzVersion
        self.fuzzFeatures = fuzzFeatures
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

public struct FuzzInitialize: Codable {
    public let header: Header
    public let state: FuzzState
    public let ancestry: [AncestryItem]

    public init(header: Header, state: FuzzState, ancestry: [AncestryItem]) {
        self.header = header
        self.state = state
        self.ancestry = ancestry
    }
}

public typealias FuzzGetState = Data32 // HeaderHash
public typealias FuzzStateRoot = Data32 // StateRootHash

public enum FuzzingMessage: Codable {
    case peerInfo(FuzzPeerInfo)
    case initialize(FuzzInitialize)
    case stateRoot(FuzzStateRoot)
    case importBlock(Block)
    case getState(FuzzGetState)
    case state(FuzzState)
    case error(String)

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let variant = try container.decode(UInt8.self)
        switch variant {
        case 0:
            self = try .peerInfo(container.decode(FuzzPeerInfo.self))
        case 1:
            self = try .initialize(container.decode(FuzzInitialize.self))
        case 2:
            self = try .stateRoot(container.decode(FuzzStateRoot.self))
        case 3:
            self = try .importBlock(container.decode(Block.self))
        case 4:
            self = try .getState(container.decode(FuzzGetState.self))
        case 5:
            self = try .state(container.decode(FuzzState.self))
        case 255:
            self = try .error(container.decode(String.self))
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid FuzzingMessage variant: \(variant)",
                ),
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        switch self {
        case let .peerInfo(value):
            try container.encode(UInt8(0))
            try container.encode(value)
        case let .initialize(value):
            try container.encode(UInt8(1))
            try container.encode(value)
        case let .stateRoot(value):
            try container.encode(UInt8(2))
            try container.encode(value)
        case let .importBlock(value):
            try container.encode(UInt8(3))
            try container.encode(value)
        case let .getState(value):
            try container.encode(UInt8(4))
            try container.encode(value)
        case let .state(value):
            try container.encode(UInt8(5))
            try container.encode(value)
        case let .error(value):
            try container.encode(UInt8(255))
            try container.encode(value)
        }
    }
}
