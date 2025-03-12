import Blockchain
import Codec
import Foundation

public struct WorkPackageSubmissionMessage: Codable, Sendable, Equatable, Hashable {
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

extension WorkPackageSubmissionMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], withConfig: ProtocolConfigRef) throws -> WorkPackageSubmissionMessage {
        guard data.count == 1, let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data"
            ))
        }
        return try JamDecoder.decode(WorkPackageSubmissionMessage.self, from: data, withConfig: withConfig)
    }
}
