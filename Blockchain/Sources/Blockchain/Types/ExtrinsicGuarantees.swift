import ScaleCodec
import Utils

public struct ExtrinsicGuarantees: Sendable {
    public struct GuaranteeItem: Sendable {
        public var coreIndex: CoreIndex
        public var workReport: WorkReport
        public var timeslot: TimeslotIndex
        public var credential: LimitedSizeArray<
            Ed25519Signature,
            ConstInt2,
            ConstInt3
        >

        public init(
            coreIndex: CoreIndex,
            workReport: WorkReport,
            timeslot: TimeslotIndex,
            credential: LimitedSizeArray<
                Ed25519Signature,
                ConstInt2,
                ConstInt3
            >
        ) {
            self.coreIndex = coreIndex
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

    public init(withConfig config: ProtocolConfigRef) {
        guarantees = ConfigLimitedSizeArray(withConfig: config)
    }
}

extension ExtrinsicGuarantees: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(withConfig config: Config) -> ExtrinsicGuarantees {
        ExtrinsicGuarantees(withConfig: config)
    }
}

extension ExtrinsicGuarantees: ScaleCodec.Encodable {
    public init(withConfig config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            guarantees: ConfigLimitedSizeArray(withConfig: config, from: &decoder) { try GuaranteeItem(withConfig: config, from: &$0) }
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(guarantees)
    }
}

extension ExtrinsicGuarantees.GuaranteeItem: ScaleCodec.Encodable {
    public init(withConfig config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            coreIndex: decoder.decode(),
            workReport: WorkReport(withConfig: config, from: &decoder),
            timeslot: decoder.decode(),
            credential: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(coreIndex)
        try encoder.encode(workReport)
        try encoder.encode(timeslot)
        try encoder.encode(credential)
    }
}
