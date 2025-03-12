import Blockchain
import Codec
import Foundation
import Networking

protocol CEMessage {
    func encode() throws -> [Data]
    static func decode(data: [Data], withConfig: ProtocolConfigRef) throws -> Self
}

public enum CERequest: Sendable, Equatable, Hashable {
    case blockRequest(BlockRequest)
    case safroleTicket1(SafroleTicketMessage)
    case safroleTicket2(SafroleTicketMessage)
    case workPackageSubmission(WorkPackageSubmissionMessage)
    case workPackageSharing(WorkPackageSharingMessage)
    case workReportDistrubution(WorkReportDistributionMessage)
}

extension CERequest: RequestProtocol {
    public typealias StreamKind = CommonEphemeralStreamKind

    public func encode() throws -> [Data] {
        switch self {
        case let .blockRequest(message):
            try message.encode()
        case let .safroleTicket1(message):
            try message.encode()
        case let .safroleTicket2(message):
            try message.encode()
        case let .workPackageSubmission(message):
            try message.encode()
        case let .workPackageSharing(message):
            try message.encode()
        case let .workReportDistrubution(message):
            try message.encode()
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
        case .workReportDistrubution:
            .workReportDistrubution
        }
    }

    static func getType(kind: CommonEphemeralStreamKind) -> CEMessage.Type {
        switch kind {
        case .blockRequest:
            BlockRequest.self
        case .safroleTicket1:
            SafroleTicketMessage.self
        case .safroleTicket2:
            SafroleTicketMessage.self
        case .workPackageSubmission:
            WorkPackageSubmissionMessage.self
        case .workPackageSharing:
            WorkPackageSharingMessage.self
        case .workReportDistrubution:
            WorkReportDistributionMessage.self
        default:
            fatalError("unimplemented")
        }
    }

    static func from(kind: CommonEphemeralStreamKind, data: any CEMessage) -> CERequest? {
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
            guard let message = data as? WorkPackageSubmissionMessage else { return nil }
            return .workPackageSubmission(message)
        case .workPackageSharing:
            guard let message = data as? WorkPackageSharingMessage else { return nil }
            return .workPackageSharing(message)
        case .workReportDistrubution:
            guard let message = data as? WorkReportDistributionMessage else { return nil }
            return .workReportDistrubution(message)
        default:
            fatalError("unimplemented")
        }
    }

    static func decodeResponseForBlockRequest(data: [Data], config: ProtocolConfigRef) throws -> [BlockRef] {
        guard data.count == 1, let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data \(data)"
            ))
        }
        let decoder = JamDecoder(data: data, config: config)
        var resp = [BlockRef]()
        while !decoder.isAtEnd {
            try resp.append(decoder.decode(BlockRef.self))
        }
        return resp
    }
}
