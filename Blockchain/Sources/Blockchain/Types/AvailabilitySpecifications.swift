import Utils

public struct AvailabilitySpecifications {
    // h
    public var workPackageHash: H256

    // l
    public var length: DataLength

    // u
    public var erasureRoot: H256

    // e
    public var segmentRoot: H256

    public init(
        workPackageHash: H256,
        length: DataLength,
        erasureRoot: H256,
        segmentRoot: H256
    ) {
        self.workPackageHash = workPackageHash
        self.length = length
        self.erasureRoot = erasureRoot
        self.segmentRoot = segmentRoot
    }
}

extension AvailabilitySpecifications: Dummy {
    public static var dummy: AvailabilitySpecifications {
        AvailabilitySpecifications(
            workPackageHash: H256(),
            length: 0,
            erasureRoot: H256(),
            segmentRoot: H256()
        )
    }
}
