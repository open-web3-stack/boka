import Blockchain
import Codec
import Dispatch
import Foundation
import Networking
import Synchronization
import TracingUtils

class UPMessageDecoder: MessageDecoder {
    typealias Message = UPMessage

    private let config: ProtocolConfigRef
    private let kind: UniquePresistentStreamKind

    init(config: ProtocolConfigRef, kind: UniquePresistentStreamKind) {
        self.config = config
        self.kind = kind
    }

    func decode(data: Data) throws -> Message {
        let type = UPMessage.getType(kind: kind)
        let payload = try JamDecoder.decode(type, from: data, withConfig: config)
        guard let message = UPMessage.from(kind: kind, data: payload) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unreachable: invalid UP message"
            ))
        }
        return message
    }
}

class CEMessageDecoder: MessageDecoder {
    typealias Message = CERequest

    private let config: ProtocolConfigRef
    private let kind: CommonEphemeralStreamKind

    init(config: ProtocolConfigRef, kind: CommonEphemeralStreamKind) {
        self.config = config
        self.kind = kind
    }

    func decode(data: Data) throws -> Message {
        let type = CERequest.getType(kind: kind)
        let payload = try JamDecoder.decode(type, from: data, withConfig: config)
        guard let message = CERequest.from(kind: kind, data: payload) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unreachable: invalid CE message"
            ))
        }
        return message
    }
}
