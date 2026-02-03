import Blockchain
import Codec
import Dispatch
import Foundation
import Networking
import Synchronization
import TracingUtils

class BlockAnnouncementDecoder: PresistentStreamMessageDecoder {
    typealias Message = UPMessage

    private let config: ProtocolConfigRef
    private let kind: UniquePresistentStreamKind
    private var handshakeReceived = false

    init(config: ProtocolConfigRef, kind: UniquePresistentStreamKind) {
        self.config = config
        self.kind = kind
    }

    func decode(data: Data) throws -> Message {
        if handshakeReceived {
            return try .blockAnnouncement(
                JamDecoder.decode(BlockAnnouncement.self, from: data, withConfig: config),
            )
        } else {
            handshakeReceived = true
            return try .blockAnnouncementHandshake(
                JamDecoder.decode(BlockAnnouncementHandshake.self, from: data, withConfig: config),
            )
        }
    }
}

class CEMessageDecoder: EphemeralStreamMessageDecoder {
    typealias Message = CERequest

    private let config: ProtocolConfigRef
    private let kind: CommonEphemeralStreamKind

    init(config: ProtocolConfigRef, kind: CommonEphemeralStreamKind) {
        self.config = config
        self.kind = kind
    }

    func decode(data: [Data]) throws -> Message {
        let type = CERequest.getType(kind: kind)
        let payload = try type.decode(data: data, config: config)
        guard let message = CERequest.from(kind: kind, data: payload) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unreachable: invalid CE message",
            ))
        }
        return message
    }
}
