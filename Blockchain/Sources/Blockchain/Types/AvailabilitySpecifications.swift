import Utils

public struct AvailabilitySpecifications: Sendable, Equatable, Codable {
    // h
    public var workPackageHash: Data32

    // l
    public var length: DataLength

    // u
    public var erasureRoot: Data32

    // e
    public var segmentRoot: Data32

    public init(
        workPackageHash: Data32,
        length: DataLength,
        erasureRoot: Data32,
        segmentRoot: Data32
    ) {
        self.workPackageHash = workPackageHash
        self.length = length
        self.erasureRoot = erasureRoot
        self.segmentRoot = segmentRoot
    }
}

extension AvailabilitySpecifications: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> AvailabilitySpecifications {
        AvailabilitySpecifications(
            workPackageHash: Data32(),
            length: 0,
            erasureRoot: Data32(),
            segmentRoot: Data32()
        )
    }
}
