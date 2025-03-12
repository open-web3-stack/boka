import Blockchain
import Codec
import Foundation

public struct WorkPackageSharingMessage: Codable, Sendable, Equatable, Hashable {
    public let coreIndex: CoreIndex
    public let bundle: WorkPackageBundle
    public let segmentsRootMappings: SegmentsRootMappings

    public init(
        coreIndex: CoreIndex,
        bundle: WorkPackageBundle,
        segmentsRootMappings: SegmentsRootMappings
    ) {
        self.coreIndex = coreIndex
        self.bundle = bundle
        self.segmentsRootMappings = segmentsRootMappings
    }
}

extension WorkPackageSharingMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], withConfig: ProtocolConfigRef) throws -> WorkPackageSharingMessage {
        guard data.count == 1, let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data"
            ))
        }
        return try JamDecoder.decode(WorkPackageSharingMessage.self, from: data, withConfig: withConfig)
    }
}
