import Blockchain
import Codec
import Foundation
import Utils

public struct AuditAnnouncementMessage: Codable, Sendable, Equatable, Hashable {
    public let headerHash: Data32
    public let tranche: UInt8
    public let announcement: Announcement
    public let evidence: Evidence

    public init(
        headerHash: Data32,
        tranche: UInt8,
        announcement: Announcement,
        evidence: Evidence
    ) {
        self.headerHash = headerHash
        self.tranche = tranche
        self.announcement = announcement
        self.evidence = evidence
    }
}

extension AuditAnnouncementMessage: CEMessage {
    public func encode() throws -> [Data] {
        let encoder = JamEncoder()
        // HeaderHash ++ Tranche ++ Announcement ++ Evidence
        try encoder.encode(headerHash)
        try encoder.encode(tranche)
        try encoder.encode(announcement)
        try encoder.encode(evidence)
        return [encoder.data]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> Self {
        guard let messageData = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data"
            ))
        }

        let decoder = JamDecoder(data: messageData, config: config)
        let headerHash = try decoder.decode(Data32.self)
        let tranche = try decoder.decode(UInt8.self)
        let announcement = try decoder.decode(Announcement.self)
        let evidence = try Evidence.decode(decoder: decoder, tranche: tranche, config: config)
        return AuditAnnouncementMessage(
            headerHash: headerHash,
            tranche: tranche,
            announcement: announcement,
            evidence: evidence
        )
    }
}
