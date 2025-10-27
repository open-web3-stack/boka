import Codec
import Utils

public struct Statistics: Sendable, Equatable, Codable {
    public struct Validator: Sendable, Equatable, Codable {
        // b: The number of blocks produced by the validator.
        public var blocks: UInt32
        // t: The number of tickets introduced by the validator.
        public var tickets: UInt32
        // p: The number of preimages introduced by the validator.
        public var preimages: UInt32
        // d: The total number of octets across all preimages introduced by the validator.
        public var preimagesBytes: UInt32
        // g: The number of reports guaranteed by the validator.
        public var guarantees: UInt32
        // a: The number of availability assurances made by the validator.
        public var assurances: UInt32

        public init(
            blocks: UInt32,
            tickets: UInt32,
            preimages: UInt32,
            preimagesBytes: UInt32,
            guarantees: UInt32,
            assurances: UInt32
        ) {
            self.blocks = blocks
            self.tickets = tickets
            self.preimages = preimages
            self.preimagesBytes = preimagesBytes
            self.guarantees = guarantees
            self.assurances = assurances
        }
    }

    public struct Core: Sendable, Equatable, Codable {
        // d: total incoming data size (package length + total segments size)
        public var dataSize: UInt

        // p: total number of assurance
        public var assuranceCount: UInt

        // i: total number of segments imported from the Segments DA
        public var importsCount: UInt

        // x: total number of the extrinsics used in computing the workload
        public var extrinsicsCount: UInt

        // z: total size in octets of the extrinsics used in computing the workload
        public var extrinsicsSize: UInt

        // e: total number of segments exported into the Segments DA
        public var exportsCount: UInt

        // b: total package data length
        public var packageSize: UInt

        // u: total actual amount of gas used during refinement
        public var gasUsed: UInt
    }

    public struct Service: Sendable, Equatable, Codable {
        public struct CountAndGas: Sendable, Equatable, Codable {
            public var count: UInt
            public var gasUsed: UInt
        }

        public struct PreimagesAndSize: Sendable, Equatable, Codable {
            public var count: UInt
            public var size: UInt
        }

        // p: total number of preimages and size
        public var preimages: PreimagesAndSize

        // r: total number of refinements and gas used
        public var refines: CountAndGas

        // i: total number of segments imported from the Segments DA
        public var importsCount: UInt

        // x: total number of the extrinsics used in computing the workload
        public var extrinsicsCount: UInt

        // z: total size in octets of the extrinsics used in computing the workload
        public var extrinsicsSize: UInt

        // e: total number of segments exported into the Segments DA
        public var exportsCount: UInt

        // a: accumulate count and gas used
        public var accumulates: CountAndGas
    }

    // validator activity statistics
    public var accumulator: ConfigFixedSizeArray<Validator, ProtocolConfig.TotalNumberOfValidators>
    public var previous: ConfigFixedSizeArray<Validator, ProtocolConfig.TotalNumberOfValidators>

    // core statistics
    public var core: ConfigFixedSizeArray<Core, ProtocolConfig.TotalNumberOfCores>

    // service statistics
    @CodingAs<SortedKeyValues<UInt32, Service>> public var service: [UInt32: Service]
}

extension Statistics: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> Statistics {
        Statistics(
            accumulator: try! ConfigFixedSizeArray(
                config: config, defaultValue: Validator.dummy(config: config)
            ),
            previous: try! ConfigFixedSizeArray(
                config: config, defaultValue: Validator.dummy(config: config)
            ),
            core: try! ConfigFixedSizeArray(
                config: config, defaultValue: Core.dummy(config: config)
            ),
            service: [:]
        )
    }
}

extension Statistics.Validator: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> Statistics.Validator {
        Statistics.Validator(
            blocks: 0,
            tickets: 0,
            preimages: 0,
            preimagesBytes: 0,
            guarantees: 0,
            assurances: 0
        )
    }
}

extension Statistics.Core: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> Statistics.Core {
        Statistics.Core(
            dataSize: 0,
            assuranceCount: 0,
            importsCount: 0,
            extrinsicsCount: 0,
            extrinsicsSize: 0,
            exportsCount: 0,
            packageSize: 0,
            gasUsed: 0
        )
    }
}

extension Statistics.Service: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> Statistics.Service {
        Statistics.Service(
            preimages: .init(count: 0, size: 0),
            refines: .init(count: 0, gasUsed: 0),
            importsCount: 0,
            extrinsicsCount: 0,
            extrinsicsSize: 0,
            exportsCount: 0,
            accumulates: .init(count: 0, gasUsed: 0),
        )
    }
}
