import Utils

// EG
public struct ExtrinsicGuarantees: Sendable, Equatable, Codable {
    public struct IndexAndSignature: Sendable, Equatable, Codable {
        // v
        public var index: ValidatorIndex
        // s
        public var signature: Ed25519Signature

        public init(
            index: ValidatorIndex,
            signature: Ed25519Signature
        ) {
            self.index = index
            self.signature = signature
        }
    }

    public struct GuaranteeItem: Sendable, Equatable, Codable {
        // w
        public var workReport: WorkReport
        // t
        public var timeslot: TimeslotIndex
        // a
        public var credential: LimitedSizeArray<
            IndexAndSignature,
            ConstInt2,
            ConstInt3
        >

        public init(
            workReport: WorkReport,
            timeslot: TimeslotIndex,
            credential: LimitedSizeArray<
                IndexAndSignature,
                ConstInt2,
                ConstInt3
            >
        ) {
            self.workReport = workReport
            self.timeslot = timeslot
            self.credential = credential
        }
    }

    public typealias GuaranteesList = ConfigLimitedSizeArray<
        GuaranteeItem,
        ProtocolConfig.Int0,
        ProtocolConfig.TotalNumberOfCores
    >

    public var guarantees: GuaranteesList

    public init(
        guarantees: GuaranteesList
    ) {
        self.guarantees = guarantees
    }
}

extension ExtrinsicGuarantees: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> ExtrinsicGuarantees {
        try! ExtrinsicGuarantees(guarantees: ConfigLimitedSizeArray(config: config))
    }
}
