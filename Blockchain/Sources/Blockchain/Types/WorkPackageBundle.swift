import Foundation
import Utils

// All the necessary data to audit a work package. Stored in audits DA
public struct WorkPackageBundle: Sendable, Equatable, Codable, Hashable {
    public var workPackage: WorkPackage
    public var extrinsic: [Data]
    public var importSegments: [Data4104]
    public var justifications: [Data]
    public init(workPackage: WorkPackage, extrinsic: [Data], importSegments: [Data4104], justifications: [Data]) {
        self.workPackage = workPackage
        self.extrinsic = extrinsic
        self.importSegments = importSegments
        self.justifications = justifications
    }
}
