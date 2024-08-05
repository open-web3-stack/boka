import ScaleCodec
import Utils

public struct Extrinsic: Sendable, Equatable {
    // ET: Tickets, used for the mechanism which manages the selection of validators for the
    // permissioning of block authoring
    public var tickets: ExtrinsicTickets

    // ED: Votes, by validators, on dispute(s) arising between them presently taking place
    public var judgements: ExtrinsicDisputes

    // EP: Static data which is presently being requested to be available for workloads to be able to fetch on demand
    public var preimages: ExtrinsicPreimages

    // EA: Assurances by each validator concerning which of the input data of workloads they have
    // correctly received and are storing locally
    public var availability: ExtrinsicAvailability

    // EG: Reports of newly completed workloads whose accuracy is guaranteed by specific validators
    public var reports: ExtrinsicGuarantees

    public init(
        tickets: ExtrinsicTickets,
        judgements: ExtrinsicDisputes,
        preimages: ExtrinsicPreimages,
        availability: ExtrinsicAvailability,
        reports: ExtrinsicGuarantees
    ) {
        self.tickets = tickets
        self.judgements = judgements
        self.preimages = preimages
        self.availability = availability
        self.reports = reports
    }
}

extension Extrinsic: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> Extrinsic {
        Extrinsic(
            tickets: ExtrinsicTickets.dummy(config: config),
            judgements: ExtrinsicDisputes.dummy(config: config),
            preimages: ExtrinsicPreimages.dummy(config: config),
            availability: ExtrinsicAvailability.dummy(config: config),
            reports: ExtrinsicGuarantees.dummy(config: config)
        )
    }
}

extension Extrinsic: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            tickets: ExtrinsicTickets(config: config, from: &decoder),
            judgements: ExtrinsicDisputes(config: config, from: &decoder),
            preimages: decoder.decode(),
            availability: ExtrinsicAvailability(config: config, from: &decoder),
            reports: ExtrinsicGuarantees(config: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(tickets)
        try encoder.encode(judgements)
        try encoder.encode(preimages)
        try encoder.encode(availability)
        try encoder.encode(reports)
    }
}
