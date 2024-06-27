import ScaleCodec
import Utils

public struct Header: Sendable {
    public struct EpochMarker: Sendable {
        public var randomness: Data32
        public var keys: ConfigFixedSizeArray<
            BandersnatchPublicKey,
            ProtocolConfig.TotalNumberOfValidators
        >

        public init(
            randomness: Data32,
            keys: ConfigFixedSizeArray<
                BandersnatchPublicKey,
                ProtocolConfig.TotalNumberOfValidators
            >
        ) {
            self.randomness = randomness
            self.keys = keys
        }
    }

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

    // Hj: The judgement marker must contain exactly the sequence of report hashes judged not as
    // confidently valid (i.e. either controversial or invalid).
    public var judgementsMarkers: [Data32]

    // Hk: a Bandersnatch block author key Hk
    public var authorKey: BandersnatchPublicKey

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
        authorKey: BandersnatchPublicKey,
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
        self.authorKey = authorKey
        self.vrfSignature = vrfSignature
        self.seal = seal
    }
}

extension Header: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(withConfig _: Config) -> Header {
        Header(
            parentHash: Data32(),
            priorStateRoot: Data32(),
            extrinsicsRoot: Data32(),
            timeslotIndex: 0,
            epoch: nil,
            winningTickets: nil,
            judgementsMarkers: [],
            authorKey: BandersnatchPublicKey(),
            vrfSignature: BandersnatchSignature(),
            seal: BandersnatchSignature()
        )
    }
}

extension Header: ScaleCodec.Encodable {
    public init(withConfig config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            parentHash: decoder.decode(),
            priorStateRoot: decoder.decode(),
            extrinsicsRoot: decoder.decode(),
            timeslotIndex: decoder.decode(),
            epoch: EpochMarker(withConfig: config, from: &decoder),
            winningTickets: ConfigFixedSizeArray(withConfig: config, from: &decoder),
            judgementsMarkers: decoder.decode(),
            authorKey: decoder.decode(),
            vrfSignature: decoder.decode(),
            seal: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(parentHash)
        try encoder.encode(priorStateRoot)
        try encoder.encode(extrinsicsRoot)
        try encoder.encode(timeslotIndex)
        try encoder.encode(epoch)
        try encoder.encode(winningTickets)
        try encoder.encode(judgementsMarkers)
        try encoder.encode(authorKey)
        try encoder.encode(vrfSignature)
        try encoder.encode(seal)
    }
}

extension Header.EpochMarker: ScaleCodec.Encodable {
    public init(withConfig config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            randomness: decoder.decode(),
            keys: ConfigFixedSizeArray(withConfig: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(randomness)
        try encoder.encode(keys)
    }
}

extension Header {
    public var hash: Data32 {
        Data32() // TODO: implement this
    }
}
