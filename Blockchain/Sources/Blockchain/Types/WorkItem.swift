import Foundation
import Utils

public struct WorkItem: Sendable, Equatable, Codable, Hashable {
    public struct ImportedDataSegment: Sendable, Equatable, Codable, Hashable {
        public enum DataSegmentRootKind: Sendable, Equatable, Hashable {
            case segmentRoot(Data32)
            case workPackageHash(Data32)
        }

        enum CodingKeys: String, CodingKey {
            case root
            case index
        }

        public var root: DataSegmentRootKind
        public var index: UInt16

        public init(root: DataSegmentRootKind, index: UInt16) {
            self.root = root
            self.index = index
        }

        // Encodable
        public func encode(to encoder: Encoder) throws {
            if encoder.isJamCodec {
                var container = encoder.unkeyedContainer()
                var indexValue = index
                switch root {
                case let .segmentRoot(root):
                    try container.encode(root)
                case let .workPackageHash(hash):
                    try container.encode(hash)
                    indexValue |= 1 << 15
                }
                try container.encode(indexValue)
            } else {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch root {
                case let .segmentRoot(root):
                    try container.encode(root, forKey: .root)
                case let .workPackageHash(hash):
                    try container.encode(hash, forKey: .root)
                }
                try container.encode(index, forKey: .index)
            }
        }

        // Decodable
        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let root = try container.decode(Data32.self)
            let index = try container.decode(UInt16.self)
            let flag = index >> 15
            if flag == 0 {
                self.root = .segmentRoot(root)
                self.index = index
            } else {
                self.root = .workPackageHash(root)
                self.index = index & 0x7FFF
            }
        }
    }

    // s
    public var serviceIndex: ServiceIndex

    // c
    public var codeHash: Data32

    // g
    public var refineGasLimit: Gas

    // a
    public var accumulateGasLimit: Gas

    // e: the number of data segments exported by this work item
    public var exportsCount: UInt16

    // y
    public var payloadBlob: Data

    // i: a sequence of imported data segments which identify a prior exported segment through an index
    public var inputs: [ImportedDataSegment]

    // x: a sequence of hashed of blob hashes and lengths to be introduced in this block
    public var outputs: [HashAndLength]

    public init(
        serviceIndex: ServiceIndex,
        codeHash: Data32,
        payloadBlob: Data,
        refineGasLimit: Gas,
        accumulateGasLimit: Gas,
        inputs: [ImportedDataSegment],
        outputs: [HashAndLength],
        exportsCount: UInt16
    ) {
        self.serviceIndex = serviceIndex
        self.codeHash = codeHash
        self.payloadBlob = payloadBlob
        self.refineGasLimit = refineGasLimit
        self.accumulateGasLimit = accumulateGasLimit
        self.inputs = inputs
        self.outputs = outputs
        self.exportsCount = exportsCount
    }
}

extension WorkItem: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> WorkItem {
        WorkItem(
            serviceIndex: 0,
            codeHash: Data32(),
            payloadBlob: Data(),
            refineGasLimit: Gas(0),
            accumulateGasLimit: Gas(0),
            inputs: [],
            outputs: [],
            exportsCount: 0
        )
    }
}
