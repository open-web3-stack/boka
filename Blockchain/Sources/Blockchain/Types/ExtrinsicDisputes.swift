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
        public var epoch: EpochIndex
        public var judgements: ConfigFixedSizeArray<
            SignatureItem,
            ProtocolConfig.TwoThirdValidatorsPlusOne
        >

        public init(
            reportHash: Data32,
            epoch: EpochIndex,
            judgements: ConfigFixedSizeArray<
                SignatureItem,
                ProtocolConfig.TwoThirdValidatorsPlusOne
            >
        ) {
            self.reportHash = reportHash
            self.epoch = epoch
            self.judgements = judgements
        }
    }

    public struct CulpritItem: Sendable, Equatable {
        public var reportHash: Data32
        public var validatorKey: Ed25519PublicKey
        public var signature: Ed25519Signature

        public init(
            reportHash: Data32,
            validatorKey: Ed25519PublicKey,
            signature: Ed25519Signature
        ) {
            self.reportHash = reportHash
            self.validatorKey = validatorKey
            self.signature = signature
        }
    }

    public struct FaultItem: Sendable, Equatable {
        public var reportHash: Data32
        public var vote: Bool
        public var validatorKey: Ed25519PublicKey
        public var signature: Ed25519Signature

        public init(
            reportHash: Data32,
            vote: Bool,
            validatorKey: Ed25519PublicKey,
            signature: Ed25519Signature
        ) {
            self.reportHash = reportHash
            self.vote = vote
            self.validatorKey = validatorKey
            self.signature = signature
        }
    }

    public var verdicts: [VerdictItem]
    public var culprits: [CulpritItem]
    public var faults: [FaultItem]

    public init(
        verdicts: [VerdictItem],
        culprits: [CulpritItem],
        faults: [FaultItem]
    ) {
        self.verdicts = verdicts
        self.culprits = culprits
        self.faults = faults
    }
}

extension ExtrinsicDisputes: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> ExtrinsicDisputes {
        ExtrinsicDisputes(verdicts: [], culprits: [], faults: [])
    }
}

extension ExtrinsicDisputes: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            verdicts: decoder.decode(.array { try VerdictItem(config: config, from: &$0) }),
            culprits: decoder.decode(.array { try CulpritItem(from: &$0) }),
            faults: decoder.decode(.array { try FaultItem(from: &$0) })
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
            epoch: decoder.decode(),
            judgements: ConfigFixedSizeArray(config: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(reportHash)
        try encoder.encode(epoch)
        try encoder.encode(judgements)
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

extension ExtrinsicDisputes.CulpritItem: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            reportHash: decoder.decode(),
            validatorKey: decoder.decode(),
            signature: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(reportHash)
        try encoder.encode(validatorKey)
        try encoder.encode(signature)
    }
}

extension ExtrinsicDisputes.FaultItem: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            reportHash: decoder.decode(),
            vote: decoder.decode(),
            validatorKey: decoder.decode(),
            signature: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(reportHash)
        try encoder.encode(vote)
        try encoder.encode(validatorKey)
        try encoder.encode(signature)
    }
}
