import Codec
import Foundation
import Utils

// L
public struct WorkDigest: Sendable, Equatable, Codable {
    // s: the index of the service whose state is to be altered and thus whose refine code was already executed
    public var serviceIndex: ServiceIndex

    // c: the hash of the code of the service at the time of being reported
    public var codeHash: Data32

    // y: the hash of the payload
    public var payloadHash: Data32

    // g: the gas prioritization ratio
    // used when determining how much gas should be allocated to execute of this item’s accumulate
    public var gasRatio: Gas

    // d: the actual output datum or error of the execution of the code
    // which may be either an octet sequence in case it was successful, or a member of the set J, if not
    public var result: WorkResult

    // u: the actual amount of gas used during refinement
    public var gasUsed: UInt

    // i: the number of segments imported from the Segments DA
    public var importsCount: UInt

    // x: the number of the extrinsics used in computing the workload
    public var extrinsicsCount: UInt

    // z: the total size in octets of the extrinsics used in computing the workload
    public var extrinsicsSize: UInt

    // e: the number of segments exported into the Segments DA
    public var exportsCount: UInt

    public init(
        serviceIndex: ServiceIndex,
        codeHash: Data32,
        payloadHash: Data32,
        gasRatio: Gas,
        result: WorkResult,
        gasUsed: UInt,
        importsCount: UInt,
        exportsCount: UInt,
        extrinsicsCount: UInt,
        extrinsicsSize: UInt
    ) {
        self.serviceIndex = serviceIndex
        self.codeHash = codeHash
        self.payloadHash = payloadHash
        self.gasRatio = gasRatio
        self.result = result
        self.gasUsed = gasUsed
        self.importsCount = importsCount
        self.exportsCount = exportsCount
        self.extrinsicsCount = extrinsicsCount
        self.extrinsicsSize = extrinsicsSize
    }
}

extension WorkDigest: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> WorkDigest {
        WorkDigest(
            serviceIndex: 0,
            codeHash: Data32(),
            payloadHash: Data32(),
            gasRatio: Gas(0),
            result: .init(.success(Data())),
            gasUsed: 0,
            importsCount: 0,
            exportsCount: 0,
            extrinsicsCount: 0,
            extrinsicsSize: 0
        )
    }
}
