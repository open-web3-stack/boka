import Foundation
import Utils

public struct SegmentsRootMapping: Sendable, Equatable, Codable, Hashable {
    public let workPackageHash: Data32
    public let segmentsRoot: Data32

    public init(workPackageHash: Data32, segmentsRoot: Data32) {
        self.workPackageHash = workPackageHash
        self.segmentsRoot = segmentsRoot
    }
}

public typealias SegmentsRootMappings = [SegmentsRootMapping]
