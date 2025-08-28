import Codec
import TracingUtils
import Utils

private let logger = Logger(label: "Header")

public struct Header: Sendable, Equatable {
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

        // Hi: block author index
        public var authorIndex: ValidatorIndex

        // Hv: the entropy-yielding vrf signature
        public var vrfSignature: BandersnatchSignature

        // Ho: The offenders markers must contain exactly the sequence of keys of all new offenders.
        public var offendersMarkers: [Ed25519PublicKey]

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
            authorIndex: ValidatorIndex,
            vrfSignature: BandersnatchSignature,
            offendersMarkers: [Ed25519PublicKey]
        ) {
            self.parentHash = parentHash
            self.priorStateRoot = priorStateRoot
            self.extrinsicsHash = extrinsicsHash
            self.timeslot = timeslot
            self.epoch = epoch
            self.winningTickets = winningTickets
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

extension Header: Codable {
    enum CodingKeys: String, CodingKey {
        case parentHash
        case priorStateRoot
        case extrinsicsHash
        case timeslot
        case epoch
        case winningTickets
        case offendersMarkers
        case authorIndex
        case vrfSignature
        case seal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            unsigned: Unsigned(
                parentHash: container.decode(Data32.self, forKey: .parentHash),
                priorStateRoot: container.decode(Data32.self, forKey: .priorStateRoot),
                extrinsicsHash: container.decode(Data32.self, forKey: .extrinsicsHash),
                timeslot: container.decode(UInt32.self, forKey: .timeslot),
                epoch: container.decodeIfPresent(EpochMarker.self, forKey: .epoch),
                winningTickets: container.decodeIfPresent(
                    ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>.self,
                    forKey: .winningTickets
                ),
                authorIndex: container.decode(ValidatorIndex.self, forKey: .authorIndex),
                vrfSignature: container.decode(BandersnatchSignature.self, forKey: .vrfSignature),
                offendersMarkers: container.decode([Ed25519PublicKey].self, forKey: .offendersMarkers),
            ),
            seal: container.decode(BandersnatchSignature.self, forKey: .seal)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(unsigned.parentHash, forKey: .parentHash)
        try container.encode(unsigned.priorStateRoot, forKey: .priorStateRoot)
        try container.encode(unsigned.extrinsicsHash, forKey: .extrinsicsHash)
        try container.encode(unsigned.timeslot, forKey: .timeslot)
        try container.encodeIfPresent(unsigned.epoch, forKey: .epoch)
        try container.encodeIfPresent(unsigned.winningTickets, forKey: .winningTickets)
        try container.encode(unsigned.authorIndex, forKey: .authorIndex)
        try container.encode(unsigned.vrfSignature, forKey: .vrfSignature)
        try container.encode(unsigned.offendersMarkers, forKey: .offendersMarkers)
        try container.encode(seal, forKey: .seal)
    }
}

extension Header: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(hash())
    }
}

extension Header: Hashable32 {
    public func hash() -> Data32 {
        do {
            return try JamEncoder.encode(self).blake2b256hash()
        } catch {
            logger.error("Failed to encode header, returning empty hash", metadata: ["error": "\(error)"])
            return Data32()
        }
    }
}

extension Header.Unsigned: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> Header.Unsigned {
        Header.Unsigned(
            parentHash: Data32(),
            priorStateRoot: Data32(),
            extrinsicsHash: Data32(),
            timeslot: 0,
            epoch: EpochMarker.dummy(config: config),
            winningTickets: nil,
            authorIndex: 0,
            vrfSignature: BandersnatchSignature(),
            offendersMarkers: []
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
    public var parentHash: Data32 { unsigned.parentHash }
    public var priorStateRoot: Data32 { unsigned.priorStateRoot }
    public var extrinsicsHash: Data32 { unsigned.extrinsicsHash }
    public var timeslot: TimeslotIndex { unsigned.timeslot }
    public var epoch: EpochMarker? { unsigned.epoch }
    public var winningTickets: ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>? { unsigned.winningTickets }
    public var offendersMarkers: [Ed25519PublicKey] { unsigned.offendersMarkers }
    public var authorIndex: ValidatorIndex { unsigned.authorIndex }
    public var vrfSignature: BandersnatchSignature { unsigned.vrfSignature }
}

extension Header: Validate {
    public enum Error: Swift.Error {
        case invalidAuthorIndex
    }

    public func validateSelf(config: ProtocolConfigRef) throws(Error) {
        guard authorIndex < UInt32(config.value.totalNumberOfValidators) else {
            throw .invalidAuthorIndex
        }
    }
}

extension Header {
    public func asRef() -> HeaderRef {
        HeaderRef(self)
    }
}

public final class HeaderRef: RefWithHash<Header>, @unchecked Sendable {
    override public var description: String {
        "Header(hash: \(hash), timeslot: \(value.timeslot))"
    }
}

extension HeaderRef: Codable {
    public convenience init(from decoder: Decoder) throws {
        try self.init(.init(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
