import Blockchain
import Codec
import Foundation

public struct WorkPackageShareMessage: Codable, Sendable, Equatable, Hashable {
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
