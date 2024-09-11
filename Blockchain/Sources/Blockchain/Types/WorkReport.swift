import Codec
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

    // o: authorization output
    public var authorizationOutput: Data

    // r: the results of the evaluation of each of the items in the package
    public var results: ConfigLimitedSizeArray<
        WorkResult,
        ProtocolConfig.Int1,
        ProtocolConfig.MaxWorkItems
    >

    public init(
        authorizerHash: Data32,
        coreIndex: CoreIndex,
        authorizationOutput: Data,
        refinementContext: RefinementContext,
        packageSpecification: AvailabilitySpecifications,
        results: ConfigLimitedSizeArray<WorkResult, ProtocolConfig.Int1, ProtocolConfig.MaxWorkItems>
    ) {
        self.authorizerHash = authorizerHash
        self.coreIndex = coreIndex
        self.authorizationOutput = authorizationOutput
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
            coreIndex: 0,
            authorizationOutput: Data(),
            refinementContext: RefinementContext.dummy(config: config),
            packageSpecification: AvailabilitySpecifications.dummy(config: config),
            results: try! ConfigLimitedSizeArray(config: config, defaultValue: WorkResult.dummy(config: config))
        )
    }
}

extension WorkReport {
    public func hash() -> Data32 {
        try! JamEncoder.encode(self).blake2b256hash()
    }
}

extension WorkReport: EncodedSize {
    public var encodedSize: Int {
        authorizerHash.encodedSize + coreIndex.encodedSize + authorizationOutput.encodedSize + refinementContext
            .encodedSize + packageSpecification
            .encodedSize + results.encodedSize
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}

extension WorkReport: Validate {
    public enum WorkReportError: Swift.Error {
        case tooBig
        case invalidCoreIndex
    }

    public func validate(config: Config) throws(WorkReportError) {
        guard encodedSize <= config.value.maxEncodedWorkReportSize else {
            throw .tooBig
        }
        guard coreIndex < UInt32(config.value.totalNumberOfCores) else {
            throw .invalidCoreIndex
        }
    }
}
