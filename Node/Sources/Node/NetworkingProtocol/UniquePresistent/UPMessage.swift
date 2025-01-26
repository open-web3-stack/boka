import Codec
import Foundation
import Networking

public enum UPMessage: Sendable {
    case blockAnnouncementHandshake(BlockAnnouncementHandshake)
    case blockAnnouncement(BlockAnnouncement)
}

extension UPMessage: MessageProtocol {
    public func encode() throws -> Data {
        switch self {
        case let .blockAnnouncementHandshake(message):
            try JamEncoder.encode(message)
        case let .blockAnnouncement(message):
            try JamEncoder.encode(message)
        }
    }

    public var kind: UniquePresistentStreamKind {
        switch self {
        case .blockAnnouncementHandshake:
            .blockAnnouncement
        case .blockAnnouncement:
            .blockAnnouncement
        }
    }
}
