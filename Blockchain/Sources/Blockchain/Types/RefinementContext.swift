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

    public var prerequistieWorkPackage: H256?

    public init(
        anchor: (
            headerHash: H256,
            stateRoot: H256,
            beefyRoot: H256
        ),
        lokupAnchor: (
            headerHash: H256,
            timeslot: TimeslotIndex
        ),
        prerequistieWorkPackage: H256?
    ) {
        self.anchor = anchor
        self.lokupAnchor = lokupAnchor
        self.prerequistieWorkPackage = prerequistieWorkPackage
    }
}

extension RefinementContext: Dummy {
    public static var dummy: RefinementContext {
        RefinementContext(
            anchor: (
                headerHash: H256(),
                stateRoot: H256(),
                beefyRoot: H256()
            ),
            lokupAnchor: (
                headerHash: H256(),
                timeslot: 0
            ),
            prerequistieWorkPackage: nil
        )
    }
}
