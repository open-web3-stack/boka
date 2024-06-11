import Utils

public struct Header {
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
    public var epoch: (
        randomness: H256,
        keys: LimitedSizeArray<
            BandersnatchPublicKey,
            Constants.TotalNumberOfValidators,
            Constants.TotalNumberOfValidators
        >
    )?

    // Hw: winning-tickets
    // The winning-tickets marker Hw is either empty or,
    // if the block is the first after the end of the submission period
    // for tickets and if the ticket accumulator is saturated, then the final sequence of ticket identifiers
    public var winningTickets: LimitedSizeArray<
        Ticket,
        Constants.EpochLength,
        Constants.EpochLength
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
}

public extension Header {
    var hash: H256 {
        H256() // TODO: implement this
    }
}
