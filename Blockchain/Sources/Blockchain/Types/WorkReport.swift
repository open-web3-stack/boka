import Foundation
import ScaleCodec
import Utils

public struct WorkReport: Sendable, Equatable {
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
            results: ConfigLimitedSizeArray(config: config, defaultValue: WorkResult.dummy(config: config))
        )
    }
}

extension WorkReport: ScaleCodec.Encodable {
    public init(config: Config, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            authorizerHash: decoder.decode(),
            output: decoder.decode(),
            refinementContext: decoder.decode(),
            packageSpecification: decoder.decode(),
            results: ConfigLimitedSizeArray(config: config, from: &decoder)
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
