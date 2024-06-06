import Utils

// A refinement context, denoted by the set X, describes the context of the chain
// at the point that the report’s corresponding work-package was evaluated.
public struct RefinementContext {
    public var anchor: (
        headerHash: H256,
        stateRoot: H256,
        beefyRoot: H256
    )

    public var lokupAnchor: (
        headerHash: H256,
        timeslot: TimeslotIndex
    )

    public var prerequistieWorkPackage: Hash?
}
