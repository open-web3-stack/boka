import Utils

public struct ExtrinsicDisputes: Sendable, Equatable, Codable {
    public struct VerdictItem: Sendable, Equatable, Codable {
        public struct SignatureItem: Sendable, Equatable, Codable {
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

    public struct CulpritItem: Sendable, Equatable, Codable {
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

    public struct FaultItem: Sendable, Equatable, Codable {
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

    // v
    public var verdicts: [VerdictItem]
    // c
    public var culprits: [CulpritItem]
    // f
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
