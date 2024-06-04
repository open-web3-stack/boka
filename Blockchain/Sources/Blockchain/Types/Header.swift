import Utils

public struct Header {
    // Hp: parent hash
    public private(set) var parentHash: H256

    // Hr: prior state root
    public private(set) var priorStateRoot: H256 // state root of the after parent block execution

    // Hx: extrinsic hash
    public private(set) var extrinsicsRoot: H256

    // Ht: timeslot index
    public private(set) var timeslotIndex: TimeslotIndex

    // He: the epoch
    // the header’s epoch marker He is either empty or, if the block is the first in a new epoch,
    // then a tuple of the epoch randomness and a sequence of Bandersnatch keys
    // defining the Bandersnatch validator keys (kb) beginning in the next epoch
    public private(set) var epoch: (randomness: H256, keys: [BandersnatchPublicKey])?

    // Hw: winning-tickets
    // The winning-tickets marker Hw is either empty or,
    // if the block is the first after the end of the submission period
    // for tickets and if the ticket accumulator is saturated, then the final sequence of ticket identifiers
    public private(set) var winningTickets: () // @TODO: figure out the type

    // Hj: judgements markers
    public private(set) var judgementsMarkers: () // @TODO: figure out the type

    // Hk: a Bandersnatch block author key Hk and two Bandersnatch signatures
    public private(set) var authorKey: () // @TODO: figure out the type

    // Hv: the entropy-yielding vrf signature
    public private(set) var vrfSignature: () // @TODO: figure out the type

    // Hs: block seal
    public private(set) var seal: () // @TODO: figure out the type
}
