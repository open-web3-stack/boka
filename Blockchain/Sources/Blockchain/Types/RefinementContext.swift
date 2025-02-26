import Codec
import Utils

// A refinement context, denoted by the set X, describes the context of the chain
// at the point that the report’s corresponding work-package was evaluated.
public struct RefinementContext: Comparable, Sendable, Equatable, Codable {
    public struct Anchor: Comparable, Sendable, Equatable, Codable, Hashable {
        // a
        public var headerHash: Data32
        // s
        public var stateRoot: Data32
        // b
        public var beefyRoot: Data32

        public init(
            headerHash: Data32,
            stateRoot: Data32,
            beefyRoot: Data32
        ) {
            self.headerHash = headerHash
            self.stateRoot = stateRoot
            self.beefyRoot = beefyRoot
        }

        public static func < (lhs: Anchor, rhs: Anchor) -> Bool {
            if lhs.headerHash != rhs.headerHash {
                return lhs.headerHash < rhs.headerHash
            }
            if lhs.stateRoot != rhs.stateRoot {
                return lhs.stateRoot < rhs.stateRoot
            }
            return lhs.beefyRoot < rhs.beefyRoot
        }
    }

    public struct LookupAnchor: Comparable, Sendable, Equatable, Codable, Hashable {
        // l
        public var headerHash: Data32
        // t
        public var timeslot: TimeslotIndex

        public init(
            headerHash: Data32,
            timeslot: TimeslotIndex
        ) {
            self.headerHash = headerHash
            self.timeslot = timeslot
        }

        public static func < (lhs: LookupAnchor, rhs: LookupAnchor) -> Bool {
            if lhs.headerHash != rhs.headerHash {
                return lhs.headerHash < rhs.headerHash
            }
            return lhs.timeslot < rhs.timeslot
        }
    }

    public var anchor: Anchor

    public var lookupAnchor: LookupAnchor

    // p
    @CodingAs<SortedSet<Data32>> public var prerequisiteWorkPackages: Set<Data32>

    public init(anchor: Anchor, lookupAnchor: LookupAnchor, prerequisiteWorkPackages: Set<Data32>) {
        self.anchor = anchor
        self.lookupAnchor = lookupAnchor
        self.prerequisiteWorkPackages = prerequisiteWorkPackages
    }

    public static func < (lhs: RefinementContext, rhs: RefinementContext) -> Bool {
        if lhs.anchor != rhs.anchor {
            return lhs.anchor < rhs.anchor
        }
        return lhs.lookupAnchor < rhs.lookupAnchor
    }
}

extension RefinementContext: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> RefinementContext {
        RefinementContext(
            anchor: Anchor(
                headerHash: Data32(),
                stateRoot: Data32(),
                beefyRoot: Data32()
            ),
            lookupAnchor: LookupAnchor(
                headerHash: Data32(),
                timeslot: 0
            ),
            prerequisiteWorkPackages: Set()
        )
    }
}

extension RefinementContext.Anchor: EncodedSize {
    public var encodedSize: Int {
        headerHash.encodedSize + stateRoot.encodedSize + beefyRoot.encodedSize
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}

extension RefinementContext.LookupAnchor: EncodedSize {
    public var encodedSize: Int {
        headerHash.encodedSize + timeslot.encodedSize
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}

extension RefinementContext: EncodedSize {
    public var encodedSize: Int {
        anchor.encodedSize + lookupAnchor.encodedSize + prerequisiteWorkPackages.encodedSize
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}
