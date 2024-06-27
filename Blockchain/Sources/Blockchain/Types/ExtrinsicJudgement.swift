import ScaleCodec
import Utils

public struct ExtrinsicJudgement: Sendable {
    public struct JudgementItem: Sendable {
        public struct SignatureItem: Sendable {
            public var isValid: Bool
            public var validatorIndex: ValidatorIndex
            public var signature: BandersnatchSignature

            public init(
                isValid: Bool,
                validatorIndex: ValidatorIndex,
                signature: BandersnatchSignature
            ) {
                self.isValid = isValid
                self.validatorIndex = validatorIndex
                self.signature = signature
            }
        }

        public var reportHash: H256
        public var signatures: ConfigFixedSizeArray<
            SignatureItem,
            ProtocolConfig.TwoThirdValidatorsPlusOne
        >

        public init(
            reportHash: H256,
            signatures: ConfigFixedSizeArray<
                SignatureItem,
                ProtocolConfig.TwoThirdValidatorsPlusOne
            >
        ) {
            self.reportHash = reportHash
            self.signatures = signatures
        }
    }

    public typealias JudgementsList = [JudgementItem]

    public var judgements: JudgementsList

    public init(
        judgements: JudgementsList
    ) {
        self.judgements = judgements
    }
}

extension ExtrinsicJudgement: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(withConfig _: Config) -> ExtrinsicJudgement {
        ExtrinsicJudgement(judgements: [])
    }
}

extension ExtrinsicJudgement: ScaleCodec.Encodable {
    public init(withConfig config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            judgements: decoder.decode(.array { try JudgementItem(withConfig: config, from: &$0) })
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(judgements)
    }
}

extension ExtrinsicJudgement.JudgementItem: ScaleCodec.Encodable {
    public init(withConfig config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            reportHash: decoder.decode(),
            signatures: ConfigFixedSizeArray(withConfig: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(reportHash)
        try encoder.encode(signatures)
    }
}

extension ExtrinsicJudgement.JudgementItem.SignatureItem: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            isValid: decoder.decode(),
            validatorIndex: decoder.decode(),
            signature: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(isValid)
        try encoder.encode(validatorIndex)
        try encoder.encode(signature)
    }
}
