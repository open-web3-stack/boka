import Blockchain
import Codec
import Foundation
import Utils

public struct PreimageAnnouncementMessage: Sendable, Equatable, Codable, Hashable {
    public let serviceID: UInt32
    public let hash: Data32
    public let preimageLength: UInt32

    public init(serviceID: UInt32, hash: Data32, preimageLength: UInt32) {
        self.serviceID = serviceID
        self.hash = hash
        self.preimageLength = preimageLength
    }
}

extension PreimageAnnouncementMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> PreimageAnnouncementMessage {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Unexpected data \(data)"
            ))
        }
        return try JamDecoder.decode(PreimageAnnouncementMessage.self, from: data, withConfig: config)
    }
}
