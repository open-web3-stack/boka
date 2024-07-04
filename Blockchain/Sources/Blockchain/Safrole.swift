import ScaleCodec
import Utils

public enum SafroleError: UInt8, Error {
    case unspecified
}

public protocol Safrole {
    var timeslot: TimeslotIndex { get }
    var entropyPool: (Data32, Data32, Data32, Data32) { get }
    var previousValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }
    var currentValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }
    var nextValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }
    var validatorQueue: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }
    var ticketsAccumulator: ConfigLimitedSizeArray<
        Ticket,
        ProtocolConfig.Int0,
        ProtocolConfig.EpochLength
    > { get }
    var ticketsOrKeys: Either<
        ConfigFixedSizeArray<
            Ticket,
            ProtocolConfig.EpochLength
        >,
        ConfigFixedSizeArray<
            BandersnatchPublicKey,
            ProtocolConfig.EpochLength
        >
    > { get }
    var ticketsVerifier: BandersnatchRingVRFRoot { get }

    func updateSafrole(slot: TimeslotIndex, entropy: Data32, extrinsics: ExtrinsicTickets)
        -> Result<
            (
                state: Self,
                epochMark: EpochMarker?,
                ticketsMark: ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>?
            ),
            SafroleError
        >
}

extension Safrole {
    public func updateSafrole(slot _: TimeslotIndex, entropy _: Data32, extrinsics _: ExtrinsicTickets)
        -> Result<
            (
                state: Self,
                epochMark: EpochMarker?,
                ticketsMark: ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>?
            ),
            SafroleError
        >
    {
        // TODO: implement
        .failure(.unspecified)
    }
}
