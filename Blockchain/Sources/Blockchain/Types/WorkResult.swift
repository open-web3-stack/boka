import Codec
import Foundation
import Utils

// L
public struct WorkResult: Sendable, Equatable, Codable {
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
    public var output: WorkOutput

    // TODO: compact encoding for these fields?

    // u: the actual amount of gas used during refinement
    public var gasUsed: UInt64

    // i: the number of segments imported from the Segments DA
    public var numImports: UInt32

    // e: the number of segments exported into the Segments DA
    public var numExports: UInt32

    // x: the number of the extrinsics used in computing the workload
    public var numExtrinsics: UInt32

    // z: and total size in octets of the extrinsics used in computing the workload
    public var extrinsicSize: UInt32

    public init(
        serviceIndex: ServiceIndex,
        codeHash: Data32,
        payloadHash: Data32,
        gasRatio: Gas,
        output: WorkOutput,
        gasUsed: UInt64,
        numImports: UInt32,
        numExports: UInt32,
        numExtrinsics: UInt32,
        extrinsicSize: UInt32
    ) {
        self.serviceIndex = serviceIndex
        self.codeHash = codeHash
        self.payloadHash = payloadHash
        self.gasRatio = gasRatio
        self.output = output
        self.gasUsed = gasUsed
        self.numImports = numImports
        self.numExports = numExports
        self.numExtrinsics = numExtrinsics
        self.extrinsicSize = extrinsicSize
    }
}

extension WorkResult: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> WorkResult {
        WorkResult(
            serviceIndex: 0,
            codeHash: Data32(),
            payloadHash: Data32(),
            gasRatio: Gas(0),
            output: .init(.success(Data())),
            gasUsed: 0,
            numImports: 0,
            numExports: 0,
            numExtrinsics: 0,
            extrinsicSize: 0
        )
    }
}
