import Foundation
import Utils

public struct WorkReport {
    // a: authorizer hash
    public var authorizerHash: H256

    // o: output
    public var output: Data

    // x: refinement context
    public var refinementContext: RefinementContext

    // s: package specification
    public var packageSpecification: AvailabilitySpecifications

    // r: the results of the evaluation of each of the items in the package
    public var results: LimitedSizeArray<
        WorkResult,
        ConstInt1,
        Constants.MaxWorkItems
    >
}
