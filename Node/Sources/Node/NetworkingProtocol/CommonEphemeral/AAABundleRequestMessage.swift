import Blockchain
import Codec
import Foundation
import Utils

/// Wrapper for Blockchain's BundleRequest to provide CEMessage conformance
/// This allows the Node module to handle bundle requests without creating
/// a circular dependency on the Blockchain module
public struct BundleRequestMessage: Codable, Sendable {
    public var erasureRoot: Data32

    public init(erasureRoot: Data32, shardIndex _: UInt16) {
        self.erasureRoot = erasureRoot
    }

    /// Convert to Blockchain's BundleRequest type
    public func toBlockchainRequest() -> BundleRequest {
        BundleRequest(erasureRoot: erasureRoot)
    }

    /// Create from Blockchain's BundleRequest type
    public static func from(blockchain request: BundleRequest) -> BundleRequestMessage {
        BundleRequestMessage(erasureRoot: request.erasureRoot, shardIndex: 0)
    }
}

extension BundleRequestMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> BundleRequestMessage {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data \(data)"
            ))
        }
        return try JamDecoder.decode(BundleRequestMessage.self, from: data, withConfig: config)
    }
}
