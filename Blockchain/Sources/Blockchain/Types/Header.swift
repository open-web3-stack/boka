import Codec
import Utils

public struct Header: Sendable, Equatable, Codable {
    // Hp: parent hash
    public var parentHash: Data32

    // Hr: prior state root
    public var priorStateRoot: Data32 // state root of the after parent block execution

    // Hx: extrinsic hash
    public var extrinsicsRoot: Data32

    // Ht: timeslot index
    public var timeslotIndex: TimeslotIndex

    // He: the epoch
    // the header’s epoch marker He is either empty or, if the block is the first in a new epoch,
    // then a tuple of the epoch randomness and a sequence of Bandersnatch keys
    // defining the Bandersnatch validator keys (kb) beginning in the next epoch
    public var epoch: EpochMarker?

    // Hw: winning-tickets
    // The winning-tickets marker Hw is either empty or,
    // if the block is the first after the end of the submission period
    // for tickets and if the ticket accumulator is saturated, then the final sequence of ticket identifiers
    public var winningTickets: ConfigFixedSizeArray<
        Ticket,
        ProtocolConfig.EpochLength
    >?

    // Hj: The verdicts markers must contain exactly the sequence of report hashes of all new
    // bad & wonky verdicts.
    public var judgementsMarkers: [Data32]

    // Ho: The offenders markers must contain exactly the sequence of keys of all new offenders.
    public var offendersMarkers: [Ed25519PublicKey]

    // Hi: block author index
    public var authorIndex: ValidatorIndex

    // Hv: the entropy-yielding vrf signature
    public var vrfSignature: BandersnatchSignature

    // Hs: block seal
    public var seal: BandersnatchSignature

    public init(
        parentHash: Data32,
        priorStateRoot: Data32,
        extrinsicsRoot: Data32,
        timeslotIndex: TimeslotIndex,
        epoch: EpochMarker?,
        winningTickets: ConfigFixedSizeArray<
            Ticket,
            ProtocolConfig.EpochLength
        >?,
        judgementsMarkers: [Data32],
        offendersMarkers: [Ed25519PublicKey],
        authorIndex: UInt32,
        vrfSignature: BandersnatchSignature,
        seal: BandersnatchSignature
    ) {
        self.parentHash = parentHash
        self.priorStateRoot = priorStateRoot
        self.extrinsicsRoot = extrinsicsRoot
        self.timeslotIndex = timeslotIndex
        self.epoch = epoch
        self.winningTickets = winningTickets
        self.judgementsMarkers = judgementsMarkers
        self.offendersMarkers = offendersMarkers
        self.authorIndex = authorIndex
        self.vrfSignature = vrfSignature
        self.seal = seal
    }
}

extension Header {
    public func asRef() -> HeaderRef {
        HeaderRef(self)
    }
}

public typealias HeaderRef = Ref<Header>

extension Header: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> Header {
        Header(
            parentHash: Data32(),
            priorStateRoot: Data32(),
            extrinsicsRoot: Data32(),
            timeslotIndex: 0,
            epoch: nil,
            winningTickets: nil,
            judgementsMarkers: [],
            offendersMarkers: [],
            authorIndex: 0,
            vrfSignature: BandersnatchSignature(),
            seal: BandersnatchSignature()
        )
    }
}

extension Header {
    public func hash() -> Data32 {
        do {
            return try blake2b256(JamEncoder.encode(self))
        } catch let e {
            fatalError("Failed to hash header: \(e)")
        }
    }
}
