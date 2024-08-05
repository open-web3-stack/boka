import ScaleCodec
import Utils

public struct ExtrinsicDisputes: Sendable, Equatable {
    public struct VerdictItem: Sendable, Equatable {
        public struct SignatureItem: Sendable, Equatable {
            public var isValid: Bool
            public var validatorIndex: ValidatorIndex
            public var signature: Ed25519Signature

            public init(
                isValid: Bool,
                validatorIndex: ValidatorIndex,
                signature: Ed25519Signature
            ) {
                self.isValid = isValid
                self.validatorIndex = validatorIndex
                self.signature = signature
            }
        }

        public var reportHash: Data32
        public var signatures: ConfigFixedSizeArray<
            SignatureItem,
            ProtocolConfig.TwoThirdValidatorsPlusOne
        >

        public init(
            reportHash: Data32,
            signatures: ConfigFixedSizeArray<
                SignatureItem,
                ProtocolConfig.TwoThirdValidatorsPlusOne
            >
        ) {
            self.reportHash = reportHash
            self.signatures = signatures
        }
    }

    public var verdicts: [VerdictItem]

    public init(
        verdicts: [VerdictItem]
    ) {
        self.verdicts = verdicts
    }
}

extension ExtrinsicDisputes: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> ExtrinsicDisputes {
        ExtrinsicDisputes(verdicts: [])
    }
}

extension ExtrinsicDisputes: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            verdicts: decoder.decode(.array { try VerdictItem(config: config, from: &$0) })
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(verdicts)
    }
}

extension ExtrinsicDisputes.VerdictItem: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            reportHash: decoder.decode(),
            signatures: ConfigFixedSizeArray(config: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(reportHash)
        try encoder.encode(signatures)
    }
}

extension ExtrinsicDisputes.VerdictItem.SignatureItem: ScaleCodec.Codable {
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
