import Blockchain
import Codec
import Foundation
import Networking

protocol CEMessage {
    func encode() throws -> [Data]
    static func decode(data: [Data], config: ProtocolConfigRef) throws -> Self
}

public enum CERequest: Sendable, Equatable, Hashable {
    case blockRequest(BlockRequest)
    case stateRequest(StateRequest)
    case safroleTicket1(SafroleTicketMessage)
    case safroleTicket2(SafroleTicketMessage)
    case workPackageSubmission(WorkPackageSubmissionMessage)
    case workPackageSharing(WorkPackageSharingMessage)
    case workReportDistribution(WorkReportDistributionMessage)
    case workReportRequest(WorkReportRequestMessage)
    case shardDistribution(ShardDistributionMessage)
    case auditShardRequest(AuditShardRequestMessage)
    case segmentShardRequest1(SegmentShardRequestMessage)
    case segmentShardRequest2(SegmentShardRequestMessage)
    case assuranceDistribution(AssuranceDistributionMessage)
    case preimageAnnouncement(PreimageAnnouncementMessage)
    case preimageRequest(PreimageRequestMessage)
    case auditAnnouncement(AuditAnnouncementMessage)
    case judgementPublication(JudgementPublicationMessage)
}

extension CERequest: RequestProtocol {
    public typealias StreamKind = CommonEphemeralStreamKind

    public func encode() throws -> [Data] {
        switch self {
        case let .blockRequest(message):
            try message.encode()
        case let .stateRequest(message):
            try message.encode()
        case let .safroleTicket1(message):
            try message.encode()
        case let .safroleTicket2(message):
            try message.encode()
        case let .workPackageSubmission(message):
            try message.encode()
        case let .workPackageSharing(message):
            try message.encode()
        case let .workReportDistribution(message):
            try message.encode()
        case let .workReportRequest(message):
            try message.encode()
        case let .shardDistribution(message):
            try message.encode()
        case let .auditShardRequest(message):
            try message.encode()
        case let .segmentShardRequest1(message):
            try message.encode()
        case let .segmentShardRequest2(message):
            try message.encode()
        case let .assuranceDistribution(message):
            try message.encode()
        case let .preimageAnnouncement(message):
            try message.encode()
        case let .preimageRequest(message):
            try message.encode()
        case let .auditAnnouncement(message):
            try message.encode()
        case let .judgementPublication(message):
            try message.encode()
        }
    }

    public var kind: CommonEphemeralStreamKind {
        switch self {
        case .blockRequest:
            .blockRequest
        case .stateRequest:
            .stateRequest
        case .safroleTicket1:
            .safroleTicket1
        case .safroleTicket2:
            .safroleTicket2
        case .workPackageSubmission:
            .workPackageSubmission
        case .workPackageSharing:
            .workPackageSharing
        case .workReportDistribution:
            .workReportDistribution
        case .workReportRequest:
            .workReportRequest
        case .shardDistribution:
            .shardDistribution
        case .auditShardRequest:
            .auditShardRequest
        case .segmentShardRequest1:
            .segmentShardRequest1
        case .segmentShardRequest2:
            .segmentShardRequest2
        case .assuranceDistribution:
            .assuranceDistribution
        case .preimageAnnouncement:
            .preimageAnnouncement
        case .preimageRequest:
            .preimageRequest
        case .auditAnnouncement:
            .auditAnnouncement
        case .judgementPublication:
            .judgementPublication
        }
    }

    static func getType(kind: CommonEphemeralStreamKind) -> CEMessage.Type {
        switch kind {
        case .blockRequest:
            BlockRequest.self
        case .stateRequest:
            StateRequest.self
        case .safroleTicket1:
            SafroleTicketMessage.self
        case .safroleTicket2:
            SafroleTicketMessage.self
        case .workPackageSubmission:
            WorkPackageSubmissionMessage.self
        case .workPackageSharing:
            WorkPackageSharingMessage.self
        case .workReportDistribution:
            WorkReportDistributionMessage.self
        case .workReportRequest:
            WorkReportRequestMessage.self
        case .shardDistribution:
            ShardDistributionMessage.self
        case .auditShardRequest:
            AuditShardRequestMessage.self
        case .segmentShardRequest1:
            SegmentShardRequestMessage.self
        case .segmentShardRequest2:
            SegmentShardRequestMessage.self
        case .assuranceDistribution:
            AssuranceDistributionMessage.self
        case .preimageAnnouncement:
            PreimageAnnouncementMessage.self
        case .preimageRequest:
            PreimageRequestMessage.self
        case .auditAnnouncement:
            AuditAnnouncementMessage.self
        case .judgementPublication:
            JudgementPublicationMessage.self
        }
    }

    static func from(kind: CommonEphemeralStreamKind, data: any CEMessage) -> CERequest? {
        switch kind {
        case .blockRequest:
            guard let message = data as? BlockRequest else { return nil }
            return .blockRequest(message)
        case .stateRequest:
            guard let message = data as? StateRequest else { return nil }
            return .stateRequest(message)
        case .safroleTicket1:
            guard let message = data as? SafroleTicketMessage else { return nil }
            return .safroleTicket1(message)
        case .safroleTicket2:
            guard let message = data as? SafroleTicketMessage else { return nil }
            return .safroleTicket2(message)
        case .workPackageSubmission:
            guard let message = data as? WorkPackageSubmissionMessage else { return nil }
            return .workPackageSubmission(message)
        case .workPackageSharing:
            guard let message = data as? WorkPackageSharingMessage else { return nil }
            return .workPackageSharing(message)
        case .workReportDistribution:
            guard let message = data as? WorkReportDistributionMessage else { return nil }
            return .workReportDistribution(message)
        case .workReportRequest:
            guard let message = data as? WorkReportRequestMessage else { return nil }
            return .workReportRequest(message)
        case .shardDistribution:
            guard let message = data as? ShardDistributionMessage else { return nil }
            return .shardDistribution(message)
        case .auditShardRequest:
            guard let message = data as? AuditShardRequestMessage else { return nil }
            return .auditShardRequest(message)
        case .segmentShardRequest1:
            guard let message = data as? SegmentShardRequestMessage else { return nil }
            return .segmentShardRequest1(message)
        case .segmentShardRequest2:
            guard let message = data as? SegmentShardRequestMessage else { return nil }
            return .segmentShardRequest2(message)
        case .assuranceDistribution:
            guard let message = data as? AssuranceDistributionMessage else { return nil }
            return .assuranceDistribution(message)
        case .preimageAnnouncement:
            guard let message = data as? PreimageAnnouncementMessage else { return nil }
            return .preimageAnnouncement(message)
        case .preimageRequest:
            guard let message = data as? PreimageRequestMessage else { return nil }
            return .preimageRequest(message)
        case .auditAnnouncement:
            guard let message = data as? AuditAnnouncementMessage else { return nil }
            return .auditAnnouncement(message)
        case .judgementPublication:
            guard let message = data as? JudgementPublicationMessage else { return nil }
            return .judgementPublication(message)
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
