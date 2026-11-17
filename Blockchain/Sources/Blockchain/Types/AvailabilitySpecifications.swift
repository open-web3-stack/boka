import Codec
import Utils

public struct AvailabilitySpecifications: Sendable, Equatable, Codable {
    /// p
    public var workPackageHash: Data32

    /// l
    public var length: DataLength

    /// u
    public var erasureRoot: Data32

    public var erasureShards: UInt16

    /// e
    public var segmentRoot: Data32

    /// n
    public var segmentCount: UInt16

    public init(
        workPackageHash: Data32,
        length: DataLength,
        erasureRoot: Data32,
        erasureShards: UInt16,
        segmentRoot: Data32,
        segmentCount: UInt16,
    ) {
        self.workPackageHash = workPackageHash
        self.length = length
        self.erasureRoot = erasureRoot
        self.erasureShards = erasureShards
        self.segmentRoot = segmentRoot
        self.segmentCount = segmentCount
    }
}

extension AvailabilitySpecifications: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> AvailabilitySpecifications {
        AvailabilitySpecifications(
            workPackageHash: Data32(),
            length: 0,
            erasureRoot: Data32(),
            erasureShards: UInt16(config.value.initialValidatorCount),
            segmentRoot: Data32(),
            segmentCount: 0,
        )
    }
}

extension AvailabilitySpecifications: EncodedSize {
    public var encodedSize: Int {
        workPackageHash.encodedSize + length.encodedSize + erasureRoot.encodedSize + erasureShards.encodedSize
            + segmentRoot.encodedSize + segmentCount.encodedSize
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}
