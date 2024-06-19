import ScaleCodec
import Utils

public struct ExtrinsicGuarantees {
    public typealias GuaranteesList = LimitedSizeArray<
        GuaranteeItem,
        ConstInt0,
        Constants.TotalNumberOfCores
    >

    public var guarantees: GuaranteesList

    public init(
        guarantees: GuaranteesList
    ) {
        self.guarantees = guarantees
    }
}

extension ExtrinsicGuarantees: Dummy {
    public static var dummy: ExtrinsicGuarantees {
        ExtrinsicGuarantees(guarantees: [])
    }
}

extension ExtrinsicGuarantees: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            guarantees: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(guarantees)
    }
}

public struct GuaranteeItem {
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

extension GuaranteeItem: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            coreIndex: decoder.decode(),
            workReport: decoder.decode(),
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
