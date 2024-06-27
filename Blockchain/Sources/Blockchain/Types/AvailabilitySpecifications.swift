import ScaleCodec
import Utils

public struct AvailabilitySpecifications: Sendable {
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
    public static func dummy(withConfig _: Config) -> AvailabilitySpecifications {
        AvailabilitySpecifications(
            workPackageHash: Data32(),
            length: 0,
            erasureRoot: Data32(),
            segmentRoot: Data32()
        )
    }
}

extension AvailabilitySpecifications: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            workPackageHash: decoder.decode(),
            length: decoder.decode(),
            erasureRoot: decoder.decode(),
            segmentRoot: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(workPackageHash)
        try encoder.encode(length)
        try encoder.encode(erasureRoot)
        try encoder.encode(segmentRoot)
    }
}
