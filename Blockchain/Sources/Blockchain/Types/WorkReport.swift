import Foundation
import Utils

public struct WorkReport: Sendable, Equatable, Codable {
    // a: authorizer hash
    public var authorizerHash: Data32

    // o: output
    public var output: Data

    // x: refinement context
    public var refinementContext: RefinementContext

    // s: package specification
    public var packageSpecification: AvailabilitySpecifications

    // r: the results of the evaluation of each of the items in the package
    public var results: ConfigLimitedSizeArray<
        WorkResult,
        ProtocolConfig.Int1,
        ProtocolConfig.MaxWorkItems
    >

    public init(
        authorizerHash: Data32,
        output: Data,
        refinementContext: RefinementContext,
        packageSpecification: AvailabilitySpecifications,
        results: ConfigLimitedSizeArray<
            WorkResult,
            ProtocolConfig.Int1,
            ProtocolConfig.MaxWorkItems
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
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> WorkReport {
        WorkReport(
            authorizerHash: Data32(),
            output: Data(),
            refinementContext: RefinementContext.dummy(config: config),
            packageSpecification: AvailabilitySpecifications.dummy(config: config),
            results: try! ConfigLimitedSizeArray(config: config, defaultValue: WorkResult.dummy(config: config))
        )
    }
}
