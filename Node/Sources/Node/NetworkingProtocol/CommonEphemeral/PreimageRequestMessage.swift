import Blockchain
import Codec
import Foundation
import Utils

public struct PreimageRequestMessage: Sendable, Equatable, Codable, Hashable {
    public let hash: Data32

    public init(hash: Data32) {
        self.hash = hash
    }
}

extension PreimageRequestMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> PreimageRequestMessage {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Unexpected data",
            ))
        }
        return try JamDecoder.decode(PreimageRequestMessage.self, from: data, withConfig: config)
    }
}
