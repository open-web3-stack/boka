import Blockchain
import Codec
import Foundation
import Utils

public struct JudgementPublicationMessage: Sendable, Equatable, Codable, Hashable {
    public let epochIndex: EpochIndex
    public let validatorIndex: ValidatorIndex
    public let validity: UInt8 // 0 = Invalid, 1 = Valid
    public let workReportHash: Data32
    public let signature: Ed25519Signature

    public init(
        epochIndex: EpochIndex,
        validatorIndex: ValidatorIndex,
        validity: UInt8,
        workReportHash: Data32,
        signature: Ed25519Signature
    ) {
        self.epochIndex = epochIndex
        self.validatorIndex = validatorIndex
        self.validity = validity
        self.workReportHash = workReportHash
        self.signature = signature
    }
}

extension JudgementPublicationMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> JudgementPublicationMessage {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Unexpected data \(data)"
            ))
        }
        return try JamDecoder.decode(JudgementPublicationMessage.self, from: data, withConfig: config)
    }
}
