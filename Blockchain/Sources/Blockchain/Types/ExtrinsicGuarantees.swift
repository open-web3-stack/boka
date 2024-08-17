import ScaleCodec
import Utils

public struct ExtrinsicGuarantees: Sendable, Equatable {
    public struct IndexAndSignature: Sendable, Equatable {
        public var index: UInt32
        public var signature: Ed25519Signature

        public init(
            index: UInt32,
            signature: Ed25519Signature
        ) {
            self.index = index
            self.signature = signature
        }
    }

    public struct GuaranteeItem: Sendable, Equatable {
        public var coreIndex: CoreIndex
        public var workReport: WorkReport
        public var timeslot: TimeslotIndex
        public var credential: LimitedSizeArray<
            IndexAndSignature,
            ConstInt2,
            ConstInt3
        >

        public init(
            coreIndex: CoreIndex,
            workReport: WorkReport,
            timeslot: TimeslotIndex,
            credential: LimitedSizeArray<
                IndexAndSignature,
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
}

extension ExtrinsicGuarantees: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> ExtrinsicGuarantees {
        try! ExtrinsicGuarantees(guarantees: ConfigLimitedSizeArray(config: config))
    }
}

extension ExtrinsicGuarantees: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            guarantees: ConfigLimitedSizeArray(config: config, from: &decoder) { try GuaranteeItem(config: config, from: &$0) }
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(guarantees)
    }
}

extension ExtrinsicGuarantees.GuaranteeItem: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            coreIndex: decoder.decode(),
            workReport: WorkReport(config: config, from: &decoder),
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

extension ExtrinsicGuarantees.IndexAndSignature: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            index: decoder.decode(),
            signature: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(index)
        try encoder.encode(signature)
    }
}
