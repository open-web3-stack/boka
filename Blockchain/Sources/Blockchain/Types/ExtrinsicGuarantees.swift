import Utils

public struct ExtrinsicGuarantees {
    public typealias GuaranteesList = LimitedSizeArray<
        (
            coreIndex: CoreIndex,
            workReport: WorkReport,
            timeslot: TimeslotIndex,
            credential: LimitedSizeArray<
                Ed25519Signature,
                ConstInt2,
                ConstInt3
            >
        ),
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
