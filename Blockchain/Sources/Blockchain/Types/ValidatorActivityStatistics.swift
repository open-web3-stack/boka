import ScaleCodec
import Utils

public struct ValidatorActivityStatistics: Sendable, Equatable {
    public struct StatisticsItem: Sendable, Equatable {
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

    public var accumulator: ConfigFixedSizeArray<StatisticsItem, ProtocolConfig.TotalNumberOfValidators>
    public var current: ConfigFixedSizeArray<StatisticsItem, ProtocolConfig.TotalNumberOfValidators>
}

extension ValidatorActivityStatistics: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> ValidatorActivityStatistics {
        ValidatorActivityStatistics(
            accumulator: ConfigFixedSizeArray(config: config),
            current: ConfigFixedSizeArray(config: config)
        )
    }
}

extension ValidatorActivityStatistics: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            accumulator: ConfigFixedSizeArray(config: config, from: &decoder),
            current: ConfigFixedSizeArray(config: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(accumulator)
        try encoder.encode(current)
    }
}

extension ValidatorActivityStatistics.StatisticsItem: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            blocks: decoder.decode(),
            tickets: decoder.decode(),
            preimages: decoder.decode(),
            preimagesBytes: decoder.decode(),
            guarantees: decoder.decode(),
            assurances: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(blocks)
        try encoder.encode(tickets)
        try encoder.encode(preimages)
        try encoder.encode(preimagesBytes)
        try encoder.encode(guarantees)
        try encoder.encode(assurances)
    }
}
