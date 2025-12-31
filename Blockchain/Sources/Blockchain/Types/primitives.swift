import Utils

public typealias Balance = Utils.Balance
public typealias ServiceIndex = UInt32
/// Timeslot index (global timeslot number across all epochs)
/// Note: Currently a typealias for UInt32. Consider creating a struct for type safety
/// to prevent confusion with other UInt32 values (EpochIndex, ServiceIndex, etc.)
public typealias TimeslotIndex = UInt32
public typealias Gas = Utils.Gas
public typealias DataLength = UInt32

public typealias ValidatorIndex = UInt16
public typealias CoreIndex = UInt16
public typealias TicketIndex = UInt8
public typealias EpochIndex = UInt32

public typealias Ed25519PublicKey = Data32
public typealias Ed25519Signature = Data64
public typealias BandersnatchPublicKey = Data32
public typealias BandersnatchSignature = Data96
public typealias BandersnatchRingVRFProof = Data784
public typealias BandersnatchRingVRFRoot = Data144
public typealias BLSKey = Data144

extension UInt32 {
    public func timeslotToEpochIndex(config: ProtocolConfigRef) -> EpochIndex {
        self / EpochIndex(config.value.epochLength)
    }

    public func epochToTimeslotIndex(config: ProtocolConfigRef) -> TimeslotIndex {
        self * TimeslotIndex(config.value.epochLength)
    }

    public func timeslotToTime(config: ProtocolConfigRef) -> UInt32 {
        self * UInt32(config.value.slotPeriodSeconds)
    }

    public func timeToTimeslot(config: ProtocolConfigRef) -> UInt32 {
        self / UInt32(config.value.slotPeriodSeconds)
    }
}
