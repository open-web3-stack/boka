import Foundation
import ScaleCodec
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

    public init(
        authorizerHash: H256,
        output: Data,
        refinementContext: RefinementContext,
        packageSpecification: AvailabilitySpecifications,
        results: LimitedSizeArray<
            WorkResult,
            ConstInt1,
            Constants.MaxWorkItems
        >
    ) {
        self.authorizerHash = authorizerHash
        self.output = output
        self.refinementContext = refinementContext
        self.packageSpecification = packageSpecification
        self.results = results
    }
}

extension WorkReport: Dummy {
    public static var dummy: WorkReport {
        WorkReport(
            authorizerHash: H256(),
            output: Data(),
            refinementContext: RefinementContext.dummy,
            packageSpecification: AvailabilitySpecifications.dummy,
            results: []
        )
    }
}

extension WorkReport: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            authorizerHash: decoder.decode(),
            output: decoder.decode(),
            refinementContext: decoder.decode(),
            packageSpecification: decoder.decode(),
            results: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(authorizerHash)
        try encoder.encode(output)
        try encoder.encode(refinementContext)
        try encoder.encode(packageSpecification)
        try encoder.encode(results)
    }
}
