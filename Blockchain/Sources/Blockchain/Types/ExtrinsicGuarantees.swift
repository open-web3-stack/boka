import Utils

public struct ExtrinsicGuarantees {
    public var guarantees: LimitedSizeArray<
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
}
