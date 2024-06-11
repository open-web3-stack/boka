import Utils

public typealias Balances = UInt64
public typealias H256 = Data32
public typealias ServiceIdentifier = H256
public typealias TimeslotIndex = UInt32
public typealias Ticket = (identifier: H256, entryIndex: TicketIndex)
public typealias Gas = UInt64
public typealias DataLength = UInt32
public typealias ValidatorIndex = UInt32 // TODO: confirm this
public typealias CoreIndex = UInt32 // TODO: confirm this
public typealias TicketIndex = UInt8 // TODO: confirm this

public typealias Ed25519PublicKey = H256
public typealias Ed25519Signature = Data64
public typealias BandersnatchPublicKey = H256
public typealias BandersnatchSignature = Data64
public typealias BandersnatchRintVRFProof = Data784
public typealias BandersnatchRingVRFRoot = H256
public typealias BLSKey = Data144
