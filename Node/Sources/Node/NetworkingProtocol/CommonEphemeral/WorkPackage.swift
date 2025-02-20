import Blockchain
import Codec
import Foundation

public struct WorkPackageMessage: Codable, Sendable, Equatable, Hashable {
    /// The core index associated with the work-package.
    public var coreIndex: CoreIndex

    /// The work-package data.
    public var workPackage: WorkPackage

    /// The extrinsic data referenced by the work-package.
    public var extrinsics: [Data]

    public init(coreIndex: CoreIndex, workPackage: WorkPackage, extrinsics: [Data]) {
        self.coreIndex = coreIndex
        self.workPackage = workPackage
        self.extrinsics = extrinsics
    }
}
