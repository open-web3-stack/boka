import Foundation
import Utils

public struct SegmentsRootMapping: Sendable, Equatable, Codable, Hashable {
    public let workPackageHash: Data32
    public let segmentsRoot: Data32
}

public typealias SegmentsRootMappings = [SegmentsRootMapping]
