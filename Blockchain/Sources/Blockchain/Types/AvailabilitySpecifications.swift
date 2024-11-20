import Codec
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

    // n
    public var segmentCount: Int

    public init(
        workPackageHash: Data32,
        length: DataLength,
        erasureRoot: Data32,
        segmentRoot: Data32,
        segmentCount: Int
    ) {
        self.workPackageHash = workPackageHash
        self.length = length
        self.erasureRoot = erasureRoot
        self.segmentRoot = segmentRoot
        self.segmentCount = segmentCount
    }
}

extension AvailabilitySpecifications: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> AvailabilitySpecifications {
        AvailabilitySpecifications(
            workPackageHash: Data32(),
            length: 0,
            erasureRoot: Data32(),
            segmentRoot: Data32(),
            segmentCount: 0
        )
    }
}

extension AvailabilitySpecifications: EncodedSize {
    public var encodedSize: Int {
        workPackageHash.encodedSize + length.encodedSize + erasureRoot.encodedSize + segmentRoot.encodedSize + segmentCount.encodedSize
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}
