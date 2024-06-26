import ScaleCodec
import Utils

public struct Header {
    public struct EpochMarker {
        public var randomness: H256
        public var keys: FixedSizeArray<
            BandersnatchPublicKey,
            Constants.TotalNumberOfValidators
        >

        public init(
            randomness: H256,
            keys: FixedSizeArray<
                BandersnatchPublicKey,
                Constants.TotalNumberOfValidators
            >
        ) {
            self.randomness = randomness
            self.keys = keys
        }
    }

    // Hp: parent hash
    public var parentHash: H256

    // Hr: prior state root
    public var priorStateRoot: H256 // state root of the after parent block execution

    // Hx: extrinsic hash
    public var extrinsicsRoot: H256

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
    public var judgementsMarkers: [H256]

    // Hk: a Bandersnatch block author key Hk
    public var authorKey: BandersnatchPublicKey

    // Hv: the entropy-yielding vrf signature
    public var vrfSignature: BandersnatchSignature

    // Hs: block seal
    public var seal: BandersnatchSignature

    public init(
        parentHash: H256,
        priorStateRoot: H256,
        extrinsicsRoot: H256,
        timeslotIndex: TimeslotIndex,
        epoch: EpochMarker?,
        winningTickets: ConfigFixedSizeArray<
            Ticket,
            ProtocolConfig.EpochLength
        >?,
        judgementsMarkers: [H256],
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
            parentHash: H256(),
            priorStateRoot: H256(),
            extrinsicsRoot: H256(),
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
            epoch: decoder.decode(),
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

extension Header.EpochMarker: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            randomness: decoder.decode(),
            keys: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(randomness)
        try encoder.encode(keys)
    }
}

public extension Header {
    var hash: H256 {
        H256() // TODO: implement this
    }
}
