import ScaleCodec
import Utils

public struct ExtrinsicJudgement {
    public typealias JudgementsList = [JudgementItem]

    public var judgements: JudgementsList

    public init(
        judgements: JudgementsList
    ) {
        self.judgements = judgements
    }
}

extension ExtrinsicJudgement: Dummy {
    public static var dummy: ExtrinsicJudgement {
        ExtrinsicJudgement(judgements: [])
    }
}

extension ExtrinsicJudgement: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            judgements: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(judgements)
    }
}

public struct JudgementItem {
    public var reportHash: H256
    public var signatures: FixedSizeArray<
        SignatureItem,
        Constants.TwoThirdValidatorsPlusOne
    >

    public init(
        reportHash: H256,
        signatures: FixedSizeArray<
            SignatureItem,
            Constants.TwoThirdValidatorsPlusOne
        >
    ) {
        self.reportHash = reportHash
        self.signatures = signatures
    }

    public struct SignatureItem {
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
}

extension JudgementItem: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            reportHash: decoder.decode(),
            signatures: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(reportHash)
        try encoder.encode(signatures)
    }
}

extension JudgementItem.SignatureItem: ScaleCodec.Codable {
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
