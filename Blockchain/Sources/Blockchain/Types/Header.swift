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
        public var extrinsicHash: Data32

        // Ht: timeslot index
        public var timeslot: TimeslotIndex

        // He: the epoch marker
        // the header’s epoch marker He is either empty or, if the block is the first in a new epoch,
        // then a tuple of the epoch randomness and a sequence of Bandersnatch keys
        // defining the Bandersnatch validator keys (kb) beginning in the next epoch
        public var epochMarker: EpochMarker?

        // Hw: winning-tickets
        // The winning-tickets marker Hw is either empty or,
        // if the block is the first after the end of the submission period
        // for tickets and if the ticket accumulator is saturated, then the final sequence of ticket identifiers
        public var winningTickets:
            ConfigFixedSizeArray<
                Ticket,
                ProtocolConfig.EpochLength,
            >?

        // Hi: block author index
        public var authorIndex: ValidatorIndex

        // Hv: the entropy-yielding vrf signature
        public var entropySource: BandersnatchSignature

        // Ho: The offenders marker must contain exactly the sequence of keys of all new offenders.
        public var offendersMarker: [Ed25519PublicKey]

        public init(
            parentHash: Data32,
            priorStateRoot: Data32,
            extrinsicHash: Data32,
            timeslot: TimeslotIndex,
            epochMarker: EpochMarker?,
            winningTickets: ConfigFixedSizeArray<
                Ticket,
                ProtocolConfig.EpochLength,
            >?,
            authorIndex: ValidatorIndex,
            entropySource: BandersnatchSignature,
            offendersMarker: [Ed25519PublicKey],
        ) {
            self.parentHash = parentHash
            self.priorStateRoot = priorStateRoot
            self.extrinsicHash = extrinsicHash
            self.timeslot = timeslot
            self.epochMarker = epochMarker
            self.winningTickets = winningTickets
            self.offendersMarker = offendersMarker
            self.authorIndex = authorIndex
            self.entropySource = entropySource
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
        case extrinsicHash
        case timeslot
        case epochMarker
        case winningTickets
        case offendersMarker
        case authorIndex
        case entropySource
        case seal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            unsigned: Unsigned(
                parentHash: container.decode(Data32.self, forKey: .parentHash),
                priorStateRoot: container.decode(Data32.self, forKey: .priorStateRoot),
                extrinsicHash: container.decode(Data32.self, forKey: .extrinsicHash),
                timeslot: container.decode(UInt32.self, forKey: .timeslot),
                epochMarker: container.decodeIfPresent(EpochMarker.self, forKey: .epochMarker),
                winningTickets: container.decodeIfPresent(
                    ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>.self,
                    forKey: .winningTickets,
                ),
                authorIndex: container.decode(ValidatorIndex.self, forKey: .authorIndex),
                entropySource: container.decode(BandersnatchSignature.self, forKey: .entropySource),
                offendersMarker: container.decode([Ed25519PublicKey].self, forKey: .offendersMarker),
            ),
            seal: container.decode(BandersnatchSignature.self, forKey: .seal),
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(unsigned.parentHash, forKey: .parentHash)
        try container.encode(unsigned.priorStateRoot, forKey: .priorStateRoot)
        try container.encode(unsigned.extrinsicHash, forKey: .extrinsicHash)
        try container.encode(unsigned.timeslot, forKey: .timeslot)
        try container.encodeIfPresent(unsigned.epochMarker, forKey: .epochMarker)
        try container.encodeIfPresent(unsigned.winningTickets, forKey: .winningTickets)
        try container.encode(unsigned.authorIndex, forKey: .authorIndex)
        try container.encode(unsigned.entropySource, forKey: .entropySource)
        try container.encode(unsigned.offendersMarker, forKey: .offendersMarker)
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
            extrinsicHash: Data32(),
            timeslot: 0,
            epochMarker: EpochMarker.dummy(config: config),
            winningTickets: nil,
            authorIndex: 0,
            entropySource: BandersnatchSignature(),
            offendersMarker: [],
        )
    }
}

extension Header: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> Header {
        Header(
            unsigned: Header.Unsigned.dummy(config: config),
            seal: BandersnatchSignature(),
        )
    }
}

extension Header {
    public var parentHash: Data32 {
        unsigned.parentHash
    }

    public var priorStateRoot: Data32 {
        unsigned.priorStateRoot
    }

    public var extrinsicHash: Data32 {
        unsigned.extrinsicHash
    }

    public var timeslot: TimeslotIndex {
        unsigned.timeslot
    }

    public var epochMarker: EpochMarker? {
        unsigned.epochMarker
    }

    public var winningTickets: ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>? {
        unsigned.winningTickets
    }

    public var offendersMarker: [Ed25519PublicKey] {
        unsigned.offendersMarker
    }

    public var authorIndex: ValidatorIndex {
        unsigned.authorIndex
    }

    public var entropySource: BandersnatchSignature {
        unsigned.entropySource
    }
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

/// Thread-safe reference wrapper for Header with cached hash
///
/// Thread-safety: @unchecked Sendable is inherited from RefWithHash<T>
/// which provides synchronization for immutable value access
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
