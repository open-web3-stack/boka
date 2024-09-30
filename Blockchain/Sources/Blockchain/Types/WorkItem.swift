import Foundation
import Utils

// I
public struct WorkItem: Sendable, Equatable, Codable {
    public struct ImportedDataSegment: Sendable, Equatable, Codable {
        public var root: Data32
        public var index: UInt16

        public init(root: Data32, index: UInt16) {
            self.root = root
            self.index = index
        }
    }

    // s
    public var serviceIndex: ServiceIndex

    // c
    public var codeHash: Data32

    // y
    public var payloadBlob: Data

    // g
    public var gasLimit: Gas

    // i: a sequence of imported data segments i identified by the root of the segments tree and an index into it
    public var inputs: [ImportedDataSegment]

    // x: a sequence of hashed of blob hashes and lengths to be introduced in this block
    public var outputs: [HashAndLength]

    // e: the number of data segments exported by this work item
    public var outputDataSegmentsCount: UInt16

    public init(
        serviceIndex: ServiceIndex,
        codeHash: Data32,
        payloadBlob: Data,
        gasLimit: Gas,
        inputs: [ImportedDataSegment],
        outputs: [HashAndLength],
        outputDataSegmentsCount: UInt16
    ) {
        self.serviceIndex = serviceIndex
        self.codeHash = codeHash
        self.payloadBlob = payloadBlob
        self.gasLimit = gasLimit
        self.inputs = inputs
        self.outputs = outputs
        self.outputDataSegmentsCount = outputDataSegmentsCount
    }
}

extension WorkItem: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> WorkItem {
        WorkItem(
            serviceIndex: 0,
            codeHash: Data32(),
            payloadBlob: Data(),
            gasLimit: Gas(0),
            inputs: [],
            outputs: [],
            outputDataSegmentsCount: 0
        )
    }
}
