import Utils

public typealias Balances = UInt64
public typealias H256 = Data32
public typealias ServiceIdentifier = H256
public typealias TimeslotIndex = UInt32
public typealias Ticket = (identifier: H256, entryIndex: UInt8)
public typealias Gas = UInt64
public typealias DataLength = UInt32

public typealias Ed25519PublicKey = H256
public typealias BandersnatchPublicKey = H256
public typealias BandersnatchSignature = Data96
public typealias BandersnatchRingVRFProof = Data196608
public typealias BLSKey = Data144
