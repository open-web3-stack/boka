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
    public let key: Data31 // [u8:31]
    public let value: Data
}

extension BoundaryNode {
    public func encode() throws -> [Data] {
        let encoder = JamEncoder()
        try encoder.encode(self)
        return [encoder.data]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> BoundaryNode {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data \(data)"
            ))
        }

        let decoder = JamDecoder(data: data, config: config)
        return try decoder.decode(BoundaryNode.self)
    }
}
