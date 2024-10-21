import Codec
import Foundation
import Networking

public enum UPMessage: Sendable {
    case blockAnnouncement(BlockAnnouncement)
}

extension UPMessage: MessageProtocol {
    public func encode() throws -> Data {
        switch self {
        case let .blockAnnouncement(message):
            try JamEncoder.encode(message)
        }
    }

    public var kind: UniquePresistentStreamKind {
        switch self {
        case .blockAnnouncement:
            .blockAnnouncement
        }
    }

    static func getType(kind: UniquePresistentStreamKind) -> Decodable.Type {
        switch kind {
        case .blockAnnouncement:
            BlockAnnouncement.self
        }
    }

    static func from(kind: UniquePresistentStreamKind, data: any Decodable) -> UPMessage? {
        switch kind {
        case .blockAnnouncement:
            guard let message = data as? BlockAnnouncement else {
                return nil
            }
            return .blockAnnouncement(message)
        }
    }
}
