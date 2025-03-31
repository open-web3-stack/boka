import Codec
import Utils

public enum Evidence: Codable, Sendable, Equatable, Hashable {
    public struct NoShow: Codable, Sendable, Equatable, Hashable {
        public let validatorIndex: ValidatorIndex
        public let previousAnnouncement: Announcement

        public init(validatorIndex: ValidatorIndex, previousAnnouncement: Announcement) {
            self.validatorIndex = validatorIndex
            self.previousAnnouncement = previousAnnouncement
        }
    }

    public struct WorkReportEvidence: Codable, Sendable, Equatable, Hashable {
        public let bandersnatchSig: BandersnatchSignature
        public let noShows: [NoShow]

        public init(bandersnatchSig: BandersnatchSignature, noShows: [NoShow]) {
            self.bandersnatchSig = bandersnatchSig
            self.noShows = noShows
        }
    }

    case firstTranche(BandersnatchSignature)
    case subsequentTranche([WorkReportEvidence])
}

extension Evidence {
    public static func decode(data: Data, tranche: UInt8, config: ProtocolConfigRef) throws -> Evidence {
        let decoder = JamDecoder(data: data, config: config)
        return try decode(decoder: decoder, tranche: tranche, config: config)
    }

    public static func decode(decoder: JamDecoder, tranche: UInt8, config _: ProtocolConfigRef) throws -> Evidence {
        if tranche == 0 {
            return try .firstTranche(decoder.decode(BandersnatchSignature.self))
        }
        return try .subsequentTranche(decoder.decode([WorkReportEvidence].self))
    }
}
