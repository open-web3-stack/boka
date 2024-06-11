public struct Extrinsic {
    // ET: Tickets, used for the mechanism which manages the selection of validators for the
    // permissioning of block authoring
    public var tickets: ExtrinsicTickets

    // EJ: Votes, by validators, on dispute(s) arising between them presently taking place
    public var judgements: ExtrinsicJudgement

    // EP: Static data which is presently being requested to be available for workloads to be able to fetch on demand
    public var preimages: ExtrinsicPreimages

    // EA: Assurances by each validator concerning which of the input data of workloads they have
    // correctly received and are storing locally
    public var availability: ExtrinsicAvailability

    // EG: Reports of newly completed workloads whose accuracy is guaranteed by specific validators
    public var reports: ExtrinsicGuarantees
}
