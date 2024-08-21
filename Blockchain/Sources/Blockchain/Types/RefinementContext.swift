import Utils

// A refinement context, denoted by the set X, describes the context of the chain
// at the point that the report’s corresponding work-package was evaluated.
public struct RefinementContext: Sendable, Equatable, Codable {
    public struct Anchor: Sendable, Equatable, Codable {
        public var headerHash: Data32
        public var stateRoot: Data32
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
    }

    public struct LokupAnchor: Sendable, Equatable, Codable {
        public var headerHash: Data32
        public var timeslot: TimeslotIndex

        public init(
            headerHash: Data32,
            timeslot: TimeslotIndex
        ) {
            self.headerHash = headerHash
            self.timeslot = timeslot
        }
    }

    public var anchor: Anchor

    public var lokupAnchor: LokupAnchor

    public var prerequistieWorkPackage: Data32?

    public init(anchor: Anchor, lokupAnchor: LokupAnchor, prerequistieWorkPackage: Data32?) {
        self.anchor = anchor
        self.lokupAnchor = lokupAnchor
        self.prerequistieWorkPackage = prerequistieWorkPackage
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
            lokupAnchor: LokupAnchor(
                headerHash: Data32(),
                timeslot: 0
            ),
            prerequistieWorkPackage: nil
        )
    }
}
