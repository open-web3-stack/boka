import Codec
import Foundation
import Utils

/// All the necessary data to audit a work package. Stored in audits DA
public struct WorkPackageBundle: Sendable, Equatable, Codable, Hashable {
    public var workPackage: WorkPackage
    public var extrinsics: [Data]
    public var importSegments: [Data4104]
    public var justifications: [Data]
    public init(workPackage: WorkPackage, extrinsics: [Data], importSegments: [Data4104], justifications: [Data]) {
        self.workPackage = workPackage
        self.extrinsics = extrinsics
        self.importSegments = importSegments
        self.justifications = justifications
    }

    public func hash() -> Data32 {
        try! JamEncoder.encode(self).blake2b256hash()
    }
}

extension WorkPackageBundle: Dummy {
    public typealias Config = ProtocolConfigRef

    public static func dummy(config: Config) -> WorkPackageBundle {
        WorkPackageBundle(
            workPackage: WorkPackage.dummy(config: config),
            extrinsics: [],
            importSegments: [],
            justifications: [],
        )
    }
}
