import Blockchain
import Codec
import Foundation

public struct WorkPackageSubmissionMessage: Sendable, Equatable, Hashable {
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
        // --> Core Index ++ Work-Package
        // --> [Extrinsic] (Message size should equal sum of extrinsic data lengths)
        let encoder = JamEncoder()
        try encoder.encode(coreIndex)
        try encoder.encode(workPackage)
        let extrinsicsEncoder = JamEncoder(capacity: extrinsics.reduce(0) { $0 + $1.count + 2 })
        for extrinsic in extrinsics {
            try extrinsicsEncoder.encode(extrinsic)
        }
        return [
            encoder.data,
            extrinsicsEncoder.data,
        ]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> WorkPackageSubmissionMessage {
        guard data.count == 2 else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data"
            ))
        }
        let decoder = JamDecoder(data: data[0], config: config)
        let coreIndex = try decoder.decode(CoreIndex.self)
        let workPackage = try decoder.decode(WorkPackage.self)
        let extrinsicsDecoder = JamDecoder(data: data[1], config: config)
        var extrinsics: [Data] = []
        while !extrinsicsDecoder.isAtEnd {
            try extrinsics.append(extrinsicsDecoder.decode(Data.self))
        }
        return .init(coreIndex: coreIndex, workPackage: workPackage, extrinsics: extrinsics)
    }
}
