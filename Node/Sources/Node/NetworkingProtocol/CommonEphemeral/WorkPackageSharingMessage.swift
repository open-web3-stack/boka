import Blockchain
import Codec
import Foundation

public struct WorkPackageSharingMessage: Sendable, Equatable, Hashable {
    public let coreIndex: CoreIndex
    public let segmentsRootMappings: SegmentsRootMappings
    public let bundle: WorkPackageBundle

    public init(
        coreIndex: CoreIndex,
        segmentsRootMappings: SegmentsRootMappings,
        bundle: WorkPackageBundle,
    ) {
        self.coreIndex = coreIndex
        self.segmentsRootMappings = segmentsRootMappings
        self.bundle = bundle
    }
}

extension WorkPackageSharingMessage: CEMessage {
    public func encode() throws -> [Data] {
        // --> Core Index ++ Segments-Root Mappings
        // --> Work-Package Bundle
        let encoder = JamEncoder()
        try encoder.encode(coreIndex)
        try encoder.encode(segmentsRootMappings)
        return try [
            encoder.data,
            JamEncoder.encode(bundle),
        ]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> WorkPackageSharingMessage {
        guard data.count == 2 else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data",
            ))
        }

        let decoder = JamDecoder(data: data[0], config: config)
        let coreIndex = try decoder.decode(CoreIndex.self)
        let segmentsRootMappings = try decoder.decode(SegmentsRootMappings.self)
        let bundle = try JamDecoder.decode(WorkPackageBundle.self, from: data[1], withConfig: config)
        return .init(coreIndex: coreIndex, segmentsRootMappings: segmentsRootMappings, bundle: bundle)
    }
}
