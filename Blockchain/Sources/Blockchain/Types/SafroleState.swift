import Utils

public struct SafroleState {
    // γk
    public var pendingValidators: FixedSizeArray<
        ValidatorKey, Constants.TotalNumberOfValidators
    >

    // γz
    public var epochRoot: BandersnatchRingVRFRoot

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

    public init(
        pendingValidators: FixedSizeArray<
            ValidatorKey, Constants.TotalNumberOfValidators
        >,
        epochRoot: BandersnatchRingVRFRoot,
        slotSealerSeries: Either<
            FixedSizeArray<
                Ticket,
                Constants.EpochLength
            >,
            FixedSizeArray<
                BandersnatchPublicKey,
                Constants.EpochLength
            >
        >,
        ticketAccumulator: LimitedSizeArray<
            Ticket,
            ConstInt0,
            Constants.EpochLength
        >
    ) {
        self.pendingValidators = pendingValidators
        self.epochRoot = epochRoot
        self.slotSealerSeries = slotSealerSeries
        self.ticketAccumulator = ticketAccumulator
    }
}

extension SafroleState: Dummy {
    public static var dummy: SafroleState {
        SafroleState(
            pendingValidators: [],
            epochRoot: BandersnatchRingVRFRoot(),
            slotSealerSeries: .left([]),
            ticketAccumulator: []
        )
    }
}
