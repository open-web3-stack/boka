import Utils

public struct ValidatorActivityStatistics: Sendable, Equatable, Codable {
    public struct StatisticsItem: Sendable, Equatable, Codable {
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

    public var accumulator:
        ConfigFixedSizeArray<StatisticsItem, ProtocolConfig.TotalNumberOfValidators>
    public var previous:
        ConfigFixedSizeArray<StatisticsItem, ProtocolConfig.TotalNumberOfValidators>
}

extension ValidatorActivityStatistics: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> ValidatorActivityStatistics {
        ValidatorActivityStatistics(
            accumulator: try! ConfigFixedSizeArray(
                config: config, defaultValue: StatisticsItem.dummy(config: config)
            ),
            previous: try! ConfigFixedSizeArray(
                config: config, defaultValue: StatisticsItem.dummy(config: config)
            )
        )
    }
}

extension ValidatorActivityStatistics.StatisticsItem: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> ValidatorActivityStatistics.StatisticsItem {
        ValidatorActivityStatistics.StatisticsItem(
            blocks: 0,
            tickets: 0,
            preimages: 0,
            preimagesBytes: 0,
            guarantees: 0,
            assurances: 0
        )
    }
}
