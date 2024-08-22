import Foundation
import Utils

public struct WorkReport: Sendable, Equatable, Codable {
    // s: package specification
    public var packageSpecification: AvailabilitySpecifications

    // x: refinement context
    public var refinementContext: RefinementContext

    // c: the core-index
    public var coreIndex: CoreIndex

    // a: authorizer hash
    public var authorizerHash: Data32

    // o: output
    public var output: Data

    // r: the results of the evaluation of each of the items in the package
    public var results: ConfigLimitedSizeArray<
        WorkResult,
        ProtocolConfig.Int1,
        ProtocolConfig.MaxWorkItems
    >

    public init(
        packageSpecification: AvailabilitySpecifications,
        refinementContext: RefinementContext,
        coreIndex: CoreIndex,
        authorizerHash: Data32,
        output: Data,
        results: ConfigLimitedSizeArray<WorkResult, ProtocolConfig.Int1, ProtocolConfig.MaxWorkItems>
    ) {
        self.packageSpecification = packageSpecification
        self.refinementContext = refinementContext
        self.coreIndex = coreIndex
        self.authorizerHash = authorizerHash
        self.output = output
        self.results = results
    }
}

extension WorkReport: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> WorkReport {
        WorkReport(
            packageSpecification: AvailabilitySpecifications.dummy(config: config),
            refinementContext: RefinementContext.dummy(config: config),
            coreIndex: 0,
            authorizerHash: Data32(),
            output: Data(),
            results: try! ConfigLimitedSizeArray(config: config, defaultValue: WorkResult.dummy(config: config))
        )
    }
}
