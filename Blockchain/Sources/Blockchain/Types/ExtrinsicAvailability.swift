import Foundation
import Utils

public struct ExtrinsicAvailability: Sendable, Equatable, Codable {
    public struct AssuranceItem: Sendable, Equatable, Codable {
        // a
        public var parentHash: Data32
        // f
        public var assurance: ConfigSizeBitString<ProtocolConfig.TotalNumberOfCores>
        // v
        public var validatorIndex: ValidatorIndex
        // s
        public var signature: Ed25519Signature

        public init(
            parentHash: Data32,
            assurance: ConfigSizeBitString<ProtocolConfig.TotalNumberOfCores>,
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

extension ExtrinsicAvailability: Validate {
    public enum Error: Swift.Error {
        case assurancesNotSorted
        case invalidValidatorIndex
    }

    public func validate(config: Config) throws(Error) {
        guard assurances.isSortedAndUnique(by: { $0.validatorIndex < $1.validatorIndex }) else {
            throw .assurancesNotSorted
        }
        for assurance in assurances {
            guard assurance.validatorIndex < UInt32(config.value.totalNumberOfValidators) else {
                throw .invalidValidatorIndex
            }
        }
    }
}
