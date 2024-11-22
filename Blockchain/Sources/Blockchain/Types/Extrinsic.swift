import Codec
import TracingUtils
import Utils

private let logger = Logger(label: "Extrinsic")

public struct Extrinsic: Sendable, Equatable, Codable {
    // ET: Tickets, used for the mechanism which manages the selection of validators for the
    // permissioning of block authoring
    public var tickets: ExtrinsicTickets

    // EP: Static data which is presently being requested to be available for workloads to be able to fetch on demand
    public var preimages: ExtrinsicPreimages

    // EG: Reports of newly completed workloads whose accuracy is guaranteed by specific validators
    public var reports: ExtrinsicGuarantees

    // EA: Assurances by each validator concerning which of the input data of workloads they have
    // correctly received and are storing locally
    public var availability: ExtrinsicAvailability

    // ED: Votes, by validators, on dispute(s) arising between them presently taking place
    public var disputes: ExtrinsicDisputes

    public init(
        tickets: ExtrinsicTickets,
        disputes: ExtrinsicDisputes,
        preimages: ExtrinsicPreimages,
        availability: ExtrinsicAvailability,
        reports: ExtrinsicGuarantees
    ) {
        self.tickets = tickets
        self.disputes = disputes
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
            disputes: ExtrinsicDisputes.dummy(config: config),
            preimages: ExtrinsicPreimages.dummy(config: config),
            availability: ExtrinsicAvailability.dummy(config: config),
            reports: ExtrinsicGuarantees.dummy(config: config)
        )
    }
}

extension Extrinsic: Validate {}

extension Extrinsic {
    public func hash() -> Data32 {
        do {
            return try JamEncoder.encode([
                JamEncoder.encode(tickets).blake2b256hash(),
                JamEncoder.encode(preimages).blake2b256hash(),
                JamEncoder.encode(reports.guarantees.array.map { item in
                    try JamEncoder.encode(item.workReport.hash()) + JamEncoder.encode(item.timeslot) + JamEncoder.encode(item.credential)
                }).blake2b256hash(),
                JamEncoder.encode(availability).blake2b256hash(),
                JamEncoder.encode(disputes).blake2b256hash(),
            ]).blake2b256hash()
        } catch {
            logger.error("Failed to encode extrinsic, returning empty hash", metadata: ["error": "\(error)"])
            return Data32()
        }
    }
}
