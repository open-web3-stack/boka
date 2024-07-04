import Foundation
import ScaleCodec
import Utils

public struct ExtrinsicAvailability: Sendable, Equatable {
    public struct AssuranceItem: Sendable, Equatable {
        // a
        public var parentHash: Data32
        // f
        public var assurance: Data // bit string with length of Constants.TotalNumberOfCores TODO: use a BitString type
        // v
        public var validatorIndex: ValidatorIndex
        // s
        public var signature: Ed25519Signature

        public init(
            parentHash: Data32,
            assurance: Data,
            validatorIndex: ValidatorIndex,
            signature: Ed25519Signature
        ) {
            self.parentHash = parentHash
            self.assurance = assurance
            self.validatorIndex = validatorIndex
            self.signature = signature
        }
    }

    public typealias AssurancesList = ConfigLimitedSizeArray<
        AssuranceItem,
        ProtocolConfig.Int0,
        ProtocolConfig.TotalNumberOfValidators
    >

    public var assurances: AssurancesList

    public init(
        assurances: AssurancesList
    ) {
        self.assurances = assurances
    }
}

extension ExtrinsicAvailability: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> ExtrinsicAvailability {
        ExtrinsicAvailability(assurances: ConfigLimitedSizeArray(config: config))
    }
}

extension ExtrinsicAvailability: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            assurances: ConfigLimitedSizeArray(config: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(assurances)
    }
}

extension ExtrinsicAvailability.AssuranceItem: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            parentHash: decoder.decode(),
            assurance: decoder.decode(),
            validatorIndex: decoder.decode(),
            signature: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(parentHash)
        try encoder.encode(assurance)
        try encoder.encode(validatorIndex)
        try encoder.encode(signature)
    }
}
