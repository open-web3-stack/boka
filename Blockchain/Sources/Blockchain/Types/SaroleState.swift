import Utils

public struct SafroleState {
    // γk
    public var pendingValidators: FixedSizeArray<
        ValidatorKey, Constants.TotalNumberOfValidators
    >

    // γz
    public var epochRoot: BandersnatchRingVRFProof

    // γs
    public var slotSealerSeries: Either<
        FixedSizeArray<
            Ticket,
            Constants.EpochLength
        >,
        FixedSizeArray<
            BandersnatchPublicKey,
            Constants.EpochLength
        >
    >

    // γa
    public var ticketAccumulator: LimitedSizeArray<
        Ticket,
        ConstInt0,
        Constants.EpochLength
    >
}
