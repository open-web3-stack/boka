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
                signature: Ed25519Signature,
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
            ProtocolConfig.TwoThirdValidatorsPlusOne,
        >

        public init(
            reportHash: Data32,
            epoch: EpochIndex,
            judgements: ConfigFixedSizeArray<
                SignatureItem,
                ProtocolConfig.TwoThirdValidatorsPlusOne,
            >,
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
            signature: Ed25519Signature,
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
            signature: Ed25519Signature,
        ) {
            self.reportHash = reportHash
            self.vote = vote
            self.validatorKey = validatorKey
            self.signature = signature
        }
    }

    /// v
    public var verdicts: [VerdictItem]
    /// c
    public var culprits: [CulpritItem]
    /// f
    public var faults: [FaultItem]

    public init(
        verdicts: [VerdictItem],
        culprits: [CulpritItem],
        faults: [FaultItem],
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

extension ExtrinsicDisputes: Validate {
    public enum Error: Swift.Error {
        case verdictsNotSorted
        case culpritsNotSorted
        case faultsNotSorted
        case judgementsNotSorted
        case invalidCulpritSignature
        case invalidFaultSignature
        case invalidPublicKey
    }

    public func validate(config _: Config) throws(Error) {
        guard verdicts.isSortedAndUnique(by: { $0.reportHash < $1.reportHash }) else {
            throw .verdictsNotSorted
        }

        guard culprits.isSortedAndUnique(by: { $0.validatorKey < $1.validatorKey }) else {
            throw .culpritsNotSorted
        }

        guard faults.isSortedAndUnique(by: { $0.validatorKey < $1.validatorKey }) else {
            throw .faultsNotSorted
        }

        for verdict in verdicts {
            guard verdict.judgements.isSortedAndUnique(by: { $0.validatorIndex < $1.validatorIndex }) else {
                throw .judgementsNotSorted
            }
        }

        for culprit in culprits {
            let payload = SigningContext.guarantee + culprit.reportHash.data
            let pubkey = try Result { try Ed25519.PublicKey(from: culprit.validatorKey) }
                .mapError { _ in Error.invalidPublicKey }
                .get()
            guard pubkey.verify(signature: culprit.signature, message: payload) else {
                throw .invalidCulpritSignature
            }
        }

        for fault in faults {
            let prefix = fault.vote ? SigningContext.valid : SigningContext.invalid
            let payload = prefix + fault.reportHash.data
            let pubkey = try Result { try Ed25519.PublicKey(from: fault.validatorKey) }
                .mapError { _ in Error.invalidPublicKey }
                .get()
            guard pubkey.verify(signature: fault.signature, message: payload) else {
                throw .invalidFaultSignature
            }
        }
    }
}
