import Codec
import Utils

public enum BoundaryNode: Sendable {
    case branch(BranchNode)
    case ext(ExtensionNode)
    case leaf(LeafNode)
}

public struct BranchNode: Codable, Sendable {
    public let children: [Data32?]
    public let value: Data?
}

public struct ExtensionNode: Codable, Sendable {
    public let prefix: Data
    public let child: Data32
}

public struct LeafNode: Codable, Sendable {
    public let key: Data31
    public let value: Data
}

extension BoundaryNode: Codable {
    enum CodingKeys: String, CodingKey {
        case branch
        case ext
        case leaf
    }

    public init(from decoder: Decoder) throws {
        if decoder.isJamCodec {
            var container = try decoder.unkeyedContainer()
            let variant = try container.decode(UInt8.self)

            switch variant {
            case 0:
                let node = try container.decode(BranchNode.self)
                self = .branch(node)
            case 1:
                let node = try container.decode(ExtensionNode.self)
                self = .ext(node)
            case 2:
                let node = try container.decode(LeafNode.self)
                self = .leaf(node)
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid BoundaryNode variant: \(variant)"
                    )
                )
            }
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let branch = try container.decodeIfPresent(BranchNode.self, forKey: .branch) {
                self = .branch(branch)
            } else if let ext = try container.decodeIfPresent(ExtensionNode.self, forKey: .ext) {
                self = .ext(ext)
            } else if let leaf = try container.decodeIfPresent(LeafNode.self, forKey: .leaf) {
                self = .leaf(leaf)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Could not decode BoundaryNode"
                    )
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        if encoder.isJamCodec {
            var container = encoder.unkeyedContainer()

            switch self {
            case let .branch(node):
                try container.encode(UInt8(0))
                try container.encode(node)
            case let .ext(node):
                try container.encode(UInt8(1))
                try container.encode(node)
            case let .leaf(node):
                try container.encode(UInt8(2))
                try container.encode(node)
            }
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case let .branch(node):
                try container.encode(node, forKey: .branch)
            case let .ext(node):
                try container.encode(node, forKey: .ext)
            case let .leaf(node):
                try container.encode(node, forKey: .leaf)
            }
        }
    }
}
