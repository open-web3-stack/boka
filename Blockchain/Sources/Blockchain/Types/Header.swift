import Codec
import TracingUtils
import Utils

private let logger = Logger(label: "Header")

public struct Header: Sendable, Equatable, Codable {
    public struct Unsigned: Sendable, Equatable, Codable {
        // Hp: parent hash
        public var parentHash: Data32

        // Hr: prior state root
        public var priorStateRoot: Data32 // state root of the after parent block execution

        // Hx: extrinsic hash
        public var extrinsicsHash: Data32

        // Ht: timeslot index
        public var timeslot: TimeslotIndex

        // He: the epoch
        // the header’s epoch marker He is either empty or, if the block is the first in a new epoch,
        // then a tuple of the epoch randomness and a sequence of Bandersnatch keys
        // defining the Bandersnatch validator keys (kb) beginning in the next epoch
        public var epoch: EpochMarker?

        // Hw: winning-tickets
        // The winning-tickets marker Hw is either empty or,
        // if the block is the first after the end of the submission period
        // for tickets and if the ticket accumulator is saturated, then the final sequence of ticket identifiers
        public var winningTickets:
            ConfigFixedSizeArray<
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

        public init(
            parentHash: Data32,
            priorStateRoot: Data32,
            extrinsicsHash: Data32,
            timeslot: TimeslotIndex,
            epoch: EpochMarker?,
            winningTickets: ConfigFixedSizeArray<
                Ticket,
                ProtocolConfig.EpochLength
            >?,
            judgementsMarkers: [Data32],
            offendersMarkers: [Ed25519PublicKey],
            authorIndex: ValidatorIndex,
            vrfSignature: BandersnatchSignature
        ) {
            self.parentHash = parentHash
            self.priorStateRoot = priorStateRoot
            self.extrinsicsHash = extrinsicsHash
            self.timeslot = timeslot
            self.epoch = epoch
            self.winningTickets = winningTickets
            self.judgementsMarkers = judgementsMarkers
            self.offendersMarkers = offendersMarkers
            self.authorIndex = authorIndex
            self.vrfSignature = vrfSignature
        }
    }

    public var unsigned: Unsigned

    // Hs: block seal
    public var seal: BandersnatchSignature

    public init(unsigned: Unsigned, seal: BandersnatchSignature) {
        self.unsigned = unsigned
        self.seal = seal
    }
}

extension Header {
    public func asRef() -> HeaderRef {
        HeaderRef(self)
    }
}

public typealias HeaderRef = Ref<Header>

extension Header.Unsigned: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> Header.Unsigned {
        Header.Unsigned(
            parentHash: Data32(),
            priorStateRoot: Data32(),
            extrinsicsHash: Data32(),
            timeslot: 0,
            epoch: nil,
            winningTickets: nil,
            judgementsMarkers: [],
            offendersMarkers: [],
            authorIndex: 0,
            vrfSignature: BandersnatchSignature()
        )
    }
}

extension Header: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> Header {
        Header(
            unsigned: Header.Unsigned.dummy(config: config),
            seal: BandersnatchSignature()
        )
    }
}

extension Header {
    public func hash() -> Data32 {
        do {
            return try JamEncoder.encode(self).blake2b256hash()
        } catch {
            logger.error("Failed to encode header, returning empty hash", metadata: ["error": "\(error)"])
            return Data32()
        }
    }

    public var parentHash: Data32 { unsigned.parentHash }
    public var priorStateRoot: Data32 { unsigned.priorStateRoot }
    public var extrinsicsHash: Data32 { unsigned.extrinsicsHash }
    public var timeslot: TimeslotIndex { unsigned.timeslot }
    public var epoch: EpochMarker? { unsigned.epoch }
    public var winningTickets: ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>? { unsigned.winningTickets }
    public var judgementsMarkers: [Data32] { unsigned.judgementsMarkers }
    public var offendersMarkers: [Ed25519PublicKey] { unsigned.offendersMarkers }
    public var authorIndex: ValidatorIndex { unsigned.authorIndex }
    public var vrfSignature: BandersnatchSignature { unsigned.vrfSignature }
}
