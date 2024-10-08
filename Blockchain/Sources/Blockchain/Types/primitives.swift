import Utils

public typealias Balance = Utils.Balance
public typealias ServiceIndex = UInt32
public typealias TimeslotIndex = UInt32 // TODO: use new type
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
