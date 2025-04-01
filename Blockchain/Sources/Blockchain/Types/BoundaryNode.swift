import Codec
import Utils

public enum BoundaryNode: Codable, Sendable {
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
