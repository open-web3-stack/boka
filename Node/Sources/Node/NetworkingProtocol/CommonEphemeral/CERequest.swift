import Blockchain
import Codec
import Foundation
import Networking

public enum CERequest: Sendable, Equatable, Hashable {
    case blockRequest(BlockRequest)
    case safroleTicket1(SafroleTicketMessage)
    case safroleTicket2(SafroleTicketMessage)
    case workPackageSubmission(WorkPackageMessage)
    case workPackageSharing(WorkPackageShareMessage)
}

extension CERequest: RequestProtocol {
    public typealias StreamKind = CommonEphemeralStreamKind

    public func encode() throws -> Data {
        switch self {
        case let .blockRequest(message):
            try JamEncoder.encode(message)
        case let .safroleTicket1(message):
            try JamEncoder.encode(message)
        case let .safroleTicket2(message):
            try JamEncoder.encode(message)
        case let .workPackageSubmission(message):
            try JamEncoder.encode(message)
        case let .workPackageSharing(message):
            try JamEncoder.encode(message)
        }
    }

    public var kind: CommonEphemeralStreamKind {
        switch self {
        case .blockRequest:
            .blockRequest
        case .safroleTicket1:
            .safroleTicket1
        case .safroleTicket2:
            .safroleTicket2
        case .workPackageSubmission:
            .workPackageSubmission
        case .workPackageSharing:
            .workPackageSharing
        }
    }

    static func getType(kind: CommonEphemeralStreamKind) -> Decodable.Type {
        switch kind {
        case .blockRequest:
            BlockRequest.self
        case .safroleTicket1:
            SafroleTicketMessage.self
        case .safroleTicket2:
            SafroleTicketMessage.self
        case .workPackageSubmission:
            WorkPackageMessage.self
        case .workPackageSharing:
            WorkPackageShareMessage.self
        default:
            fatalError("unimplemented")
        }
    }

    static func from(kind: CommonEphemeralStreamKind, data: any Decodable) -> CERequest? {
        switch kind {
        case .blockRequest:
            guard let message = data as? BlockRequest else {
                return nil
            }
            return .blockRequest(message)
        case .safroleTicket1:
            guard let message = data as? SafroleTicketMessage else {
                return nil
            }
            return .safroleTicket1(message)
        case .safroleTicket2:
            guard let message = data as? SafroleTicketMessage else {
                return nil
            }
            return .safroleTicket2(message)
        case .workPackageSubmission:
            guard let message = data as? WorkPackageMessage else { return nil }
            return .workPackageSubmission(message)
        case .workPackageSharing:
            guard let message = data as? WorkPackageShareMessage else { return nil }
            return .workPackageSharing(message)
        default:
            fatalError("unimplemented")
        }
    }

    static func decodeResponseForBlockRequest(data: Data, config: ProtocolConfigRef) throws -> [BlockRef] {
        let decoder = JamDecoder(data: data, config: config)
        var resp = [BlockRef]()
        while !decoder.isAtEnd {
            try resp.append(decoder.decode(BlockRef.self))
        }
        return resp
    }
}
