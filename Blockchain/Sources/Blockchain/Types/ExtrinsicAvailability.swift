import Foundation
import Utils

public struct ExtrinsicAvailability: Sendable, Equatable, Codable {
    public struct AssuranceItem: Sendable, Equatable, Codable {
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
        try! ExtrinsicAvailability(assurances: ConfigLimitedSizeArray(config: config))
    }
}
