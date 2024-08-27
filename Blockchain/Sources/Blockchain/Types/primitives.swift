import Utils

public typealias Balance = UInt64
public typealias ServiceIndex = UInt32
public typealias TimeslotIndex = UInt32
public typealias Gas = UInt64
public typealias DataLength = UInt32

public typealias ValidatorIndex = UInt16
public typealias CoreIndex = UInt32 // TODO: confirm this
public typealias TicketIndex = UInt8
public typealias EpochIndex = UInt32

public typealias Ed25519PublicKey = Data32
public typealias Ed25519Signature = Data64
public typealias BandersnatchPublicKey = Data32
public typealias BandersnatchSignature = Data64
public typealias BandersnatchRingVRFProof = Data784
public typealias BandersnatchRingVRFRoot = Data144
public typealias BLSKey = Data144
