import Codec
import Utils

public enum Evidence: Sendable, Equatable, Hashable {
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

extension Evidence: Codable {
    public init(from decoder: Decoder) throws {
        if decoder.isJamCodec {
            var container = try decoder.unkeyedContainer()

            if let signature = try? container.decode(BandersnatchSignature.self) {
                self = .firstTranche(signature)
                return
            }
            container = try decoder.unkeyedContainer()
            if let evidences = try? container.decode([WorkReportEvidence].self) {
                self = .subsequentTranche(evidences)
                return
            }

            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Could not decode Evidence as either firstTranche or subsequentTranche"
                )
            )
        } else {
            let container = try decoder.singleValueContainer()

            if let signature = try? container.decode(BandersnatchSignature.self) {
                self = .firstTranche(signature)
                return
            }

            if let evidences = try? container.decode([WorkReportEvidence].self) {
                self = .subsequentTranche(evidences)
                return
            }

            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Could not decode Evidence as either BandersnatchSignature or [WorkReportEvidence]"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        if encoder.isJamCodec {
            var container = encoder.unkeyedContainer()
            switch self {
            case let .firstTranche(signature):
                try container.encode(signature)
            case let .subsequentTranche(evidences):
                try container.encode(evidences)
            }
        } else {
            var container = encoder.singleValueContainer()
            switch self {
            case let .firstTranche(signature):
                try container.encode(signature)
            case let .subsequentTranche(evidences):
                try container.encode(evidences)
            }
        }
    }
}
