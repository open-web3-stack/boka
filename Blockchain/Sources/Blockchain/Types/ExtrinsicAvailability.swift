import Foundation
import Utils

public struct ExtrinsicAvailability {
    public typealias AssurancesList = LimitedSizeArray<
        (
            // a
            parentHash: H256,

            // f
            assurance: Data, // bit string with length of Constants.TotalNumberOfCores
            // TODO: use a BitString type

            // v
            validatorIndex: ValidatorIndex,

            // s
            signature: Ed25519Signature
        ),
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
