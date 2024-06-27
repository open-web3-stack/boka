import Utils

public typealias Balances = UInt64
public typealias ServiceIdentifier = Data32
public typealias TimeslotIndex = UInt32
public typealias Gas = UInt64
public typealias DataLength = UInt32
public typealias ValidatorIndex = UInt32 // TODO: confirm this
public typealias CoreIndex = UInt32 // TODO: confirm this
public typealias TicketIndex = UInt8 // TODO: confirm this

public typealias Ed25519PublicKey = Data32
public typealias Ed25519Signature = Data64
public typealias BandersnatchPublicKey = Data32
public typealias BandersnatchSignature = Data64
public typealias BandersnatchRintVRFProof = Data784
public typealias BandersnatchRingVRFRoot = Data32
public typealias BLSKey = Data144
