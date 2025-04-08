import Codec
import Foundation
import Utils

public final class WorkReportRef: RefWithHash<WorkReport>, @unchecked Sendable {
    public var packageSpecification: AvailabilitySpecifications { value.packageSpecification }
    public var refinementContext: RefinementContext { value.refinementContext }
    public var coreIndex: CoreIndex { value.coreIndex }
    public var authorizerHash: Data32 { value.authorizerHash }
    public var authorizationOutput: Data { value.authorizationOutput }
    public var lookup: [Data32: Data32] { value.lookup }
    public var results: ConfigLimitedSizeArray<WorkResult, ProtocolConfig.Int1, ProtocolConfig.MaxWorkItems> { value.results }
    public var authGasUsed: UInt { value.authGasUsed }

    public convenience init(
        authorizerHash: Data32,
        coreIndex: CoreIndex,
        authorizationOutput: Data,
        refinementContext: RefinementContext,
        packageSpecification: AvailabilitySpecifications,
        lookup: [Data32: Data32],
        results: ConfigLimitedSizeArray<WorkResult, ProtocolConfig.Int1, ProtocolConfig.MaxWorkItems>,
        authGasUsed: UInt
    ) {
        self.init(WorkReport(
            authorizerHash: authorizerHash,
            coreIndex: coreIndex,
            authorizationOutput: authorizationOutput,
            refinementContext: refinementContext,
            packageSpecification: packageSpecification,
            lookup: lookup,
            results: results,
            authGasUsed: authGasUsed
        ))
    }
}

extension WorkReportRef: Codable {
    public convenience init(from decoder: Decoder) throws {
        try self.init(WorkReport(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

extension WorkReportRef {
    public func validate(config: ProtocolConfigRef) throws {
        try value.validate(config: config)
    }
}

extension WorkReportRef {
    public static func dummy(config: ProtocolConfigRef) -> WorkReportRef {
        WorkReportRef(
            authorizerHash: Data32(),
            coreIndex: 0,
            authorizationOutput: Data(),
            refinementContext: RefinementContext.dummy(config: config),
            packageSpecification: AvailabilitySpecifications.dummy(config: config),
            lookup: [:],
            results: try! ConfigLimitedSizeArray(
                config: config,
                defaultValue: WorkResult.dummy(config: config)
            ),
            authGasUsed: 0
        )
    }
}
