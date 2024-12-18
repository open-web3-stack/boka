import Foundation
import Utils

// All the necessary data to audit a work package. Stored in audits DA
public struct WorkPackageBundle: Sendable, Equatable, Codable {
    public var workPackage: WorkPackage
    public var extrinsic: [Data]
    public var importSegments: [[Data]]
    public var justifications: [[Data]]
}
