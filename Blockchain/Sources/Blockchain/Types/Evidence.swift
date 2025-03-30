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
    public func encode() throws -> Data {
        let encoder = JamEncoder()
        switch self {
        case let .firstTranche(signature):
            try encoder.encode(signature)

        case let .subsequentTranche(evidences):
            // BandersnatchSignature ++ len ++ [NoShow]
            for evidence in evidences {
                try encoder.encode(evidence.bandersnatchSig)
                try encoder.encode(UInt32(evidence.noShows.count))
                for noShow in evidence.noShows {
                    try encoder.encode(noShow.validatorIndex)
                    try encoder.encode(noShow.previousAnnouncement)
                }
            }
        }
        return encoder.data
    }

    public static func decode(data: Data, tranche: UInt8, config: ProtocolConfigRef) throws -> Evidence {
        let decoder = JamDecoder(data: data)
        return try decode(decoder: decoder, tranche: tranche, config: config)
    }

    public static func decode(decoder: JamDecoder, tranche: UInt8, config _: ProtocolConfigRef) throws -> Evidence {
        if tranche == 0 {
            return try .firstTranche(decoder.decode(BandersnatchSignature.self))
        }

        var evidences = [WorkReportEvidence]()
        while !decoder.isAtEnd {
            let signature = try decoder.decode(BandersnatchSignature.self)
            let noShowCount = try decoder.decode(UInt32.self)
            var noShows = [NoShow]()

            for _ in 0 ..< noShowCount {
                try noShows.append(NoShow(
                    validatorIndex: decoder.decode(ValidatorIndex.self),
                    previousAnnouncement: decoder.decode(Announcement.self)
                ))
            }

            evidences.append(WorkReportEvidence(
                bandersnatchSig: signature,
                noShows: noShows
            ))
        }

        return .subsequentTranche(evidences)
    }
}

// extension Evidence {
//
//    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> Evidence {
//        guard let data = data.first else {
//            throw DecodingError.dataCorrupted(DecodingError.Context(
//                codingPath: [],
//                debugDescription: "unexpected data \(data)"
//            ))
//        }
//
//        let decoder = JamDecoder(data: data, config: config)
//
//        if data.count == ConstInt96.value {
//            return try .firstTranche(decoder.decode(BandersnatchSignature.self))
//        }
//
//        var evidences = [WorkReportEvidence]()
//        while !decoder.isAtEnd {
//            let signature = try decoder.decode(BandersnatchSignature.self)
//            let noShowCount = try decoder.decode(UInt32.self)
//            var noShows = [NoShow]()
//
//            for _ in 0 ..< noShowCount {
//                try noShows.append(NoShow(
//                    validatorIndex: decoder.decode(ValidatorIndex.self),
//                    previousAnnouncement: decoder.decode(Announcement.self)
//                ))
//            }
//
//            evidences.append(WorkReportEvidence(
//                bandersnatchSig: signature,
//                noShows: noShows
//            ))
//        }
//
//        return .subsequentTranche(evidences)
//    }
// }
