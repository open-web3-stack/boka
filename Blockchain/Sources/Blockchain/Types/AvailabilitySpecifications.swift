import ScaleCodec
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
    public typealias Config = ProtocolConfigRef
    public static func dummy(withConfig _: Config) -> AvailabilitySpecifications {
        AvailabilitySpecifications(
            workPackageHash: H256(),
            length: 0,
            erasureRoot: H256(),
            segmentRoot: H256()
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
