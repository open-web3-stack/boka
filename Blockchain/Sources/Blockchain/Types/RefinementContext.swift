import ScaleCodec
import Utils

// A refinement context, denoted by the set X, describes the context of the chain
// at the point that the report’s corresponding work-package was evaluated.
public struct RefinementContext: Sendable {
    public var anchor: (
        headerHash: Data32,
        stateRoot: Data32,
        beefyRoot: Data32
    )

    public var lokupAnchor: (
        headerHash: Data32,
        timeslot: TimeslotIndex
    )

    public var prerequistieWorkPackage: Data32?

    public init(
        anchor: (
            headerHash: Data32,
            stateRoot: Data32,
            beefyRoot: Data32
        ),
        lokupAnchor: (
            headerHash: Data32,
            timeslot: TimeslotIndex
        ),
        prerequistieWorkPackage: Data32?
    ) {
        self.anchor = anchor
        self.lokupAnchor = lokupAnchor
        self.prerequistieWorkPackage = prerequistieWorkPackage
    }
}

extension RefinementContext: Equatable {
    public static func == (lhs: RefinementContext, rhs: RefinementContext) -> Bool {
        lhs.anchor == rhs.anchor && lhs.lokupAnchor == rhs.lokupAnchor && lhs.prerequistieWorkPackage == rhs.prerequistieWorkPackage
    }
}

extension RefinementContext: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> RefinementContext {
        RefinementContext(
            anchor: (
                headerHash: Data32(),
                stateRoot: Data32(),
                beefyRoot: Data32()
            ),
            lokupAnchor: (
                headerHash: Data32(),
                timeslot: 0
            ),
            prerequistieWorkPackage: nil
        )
    }
}

extension RefinementContext: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            anchor: decoder.decode(),
            lokupAnchor: decoder.decode(),
            prerequistieWorkPackage: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(anchor)
        try encoder.encode(lokupAnchor)
        try encoder.encode(prerequistieWorkPackage)
    }
}
