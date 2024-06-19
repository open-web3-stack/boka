import Foundation
import ScaleCodec
import Utils

public struct ExtrinsicAvailability {
    public typealias AssurancesList = LimitedSizeArray<
        AssuranceItem,
        ConstInt0,
        Constants.TotalNumberOfValidators
    >

    public var assurances: AssurancesList

    public init(
        assurances: AssurancesList
    ) {
        self.assurances = assurances
    }
}

extension ExtrinsicAvailability: Dummy {
    public static var dummy: ExtrinsicAvailability {
        ExtrinsicAvailability(assurances: [])
    }
}

extension ExtrinsicAvailability: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            assurances: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(assurances)
    }
}

public struct AssuranceItem {
    // a
    public var parentHash: H256
    // f
    public var assurance: Data // bit string with length of Constants.TotalNumberOfCores TODO: use a BitString type
    // v
    public var validatorIndex: ValidatorIndex
    // s
    public var signature: Ed25519Signature

    public init(
        parentHash: H256,
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

extension AssuranceItem: ScaleCodec.Codable {
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
