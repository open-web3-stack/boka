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
    enum CodingKeys: String, CodingKey {
        case firstTranche
        case subsequentTranche
    }

    enum EvidenceCodingError: Error {
        case invalidVariant
    }

    public init(from decoder: Decoder) throws {
        if decoder.isJamCodec {
            var container = try decoder.unkeyedContainer()
            let variant = try container.decode(UInt8.self)
            switch variant {
            case 0:
                let signature = try container.decode(BandersnatchSignature.self)
                self = .firstTranche(signature)
            case 1:
                let evidences = try container.decode([WorkReportEvidence].self)
                self = .subsequentTranche(evidences)
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid Evidence variant: \(variant)",
                    ),
                )
            }
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.firstTranche) {
                let signature = try container.decode(BandersnatchSignature.self, forKey: .firstTranche)
                self = .firstTranche(signature)
            } else if container.contains(.subsequentTranche) {
                let evidences = try container.decode([WorkReportEvidence].self, forKey: .subsequentTranche)
                self = .subsequentTranche(evidences)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "No valid Evidence variant found",
                    ),
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        if encoder.isJamCodec {
            var container = encoder.unkeyedContainer()
            switch self {
            case let .firstTranche(signature):
                try container.encode(UInt8(0))
                try container.encode(signature)
            case let .subsequentTranche(evidences):
                try container.encode(UInt8(1))
                try container.encode(evidences)
            }
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .firstTranche(signature):
                try container.encode(signature, forKey: .firstTranche)
            case let .subsequentTranche(evidences):
                try container.encode(evidences, forKey: .subsequentTranche)
            }
        }
    }
}
