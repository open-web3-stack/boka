import Codec
import Foundation
import Utils

public struct WorkReport: Sendable, Equatable, Codable, Hashable {
    // s: package specification
    public var packageSpecification: AvailabilitySpecifications

    // x: refinement context
    public var refinementContext: RefinementContext

    // c: the core-index
    public var coreIndex: CoreIndex

    // a: authorizer hash
    public var authorizerHash: Data32

    // o: authorizer trace
    public var authorizerTrace: Data

    // l: segment-root lookup dictionary
    @CodingAs<SortedKeyValues<Data32, Data32>> public var lookup: [Data32: Data32]

    // r: the results of the evaluation of each of the items in the package
    public var digests: ConfigLimitedSizeArray<
        WorkDigest,
        ProtocolConfig.Int1,
        ProtocolConfig.MaxWorkItems
    >

    // g
    public var authGasUsed: UInt

    public init(
        authorizerHash: Data32,
        coreIndex: CoreIndex,
        authorizerTrace: Data,
        refinementContext: RefinementContext,
        packageSpecification: AvailabilitySpecifications,
        lookup: [Data32: Data32],
        digests: ConfigLimitedSizeArray<WorkDigest, ProtocolConfig.Int1, ProtocolConfig.MaxWorkItems>,
        authGasUsed: UInt
    ) {
        self.authorizerHash = authorizerHash
        self.coreIndex = coreIndex
        self.authorizerTrace = authorizerTrace
        self.refinementContext = refinementContext
        self.packageSpecification = packageSpecification
        self.lookup = lookup
        self.digests = digests
        self.authGasUsed = authGasUsed
    }
}

extension WorkReport: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> WorkReport {
        WorkReport(
            authorizerHash: Data32(),
            coreIndex: 0,
            authorizerTrace: Data(),
            refinementContext: RefinementContext.dummy(config: config),
            packageSpecification: AvailabilitySpecifications.dummy(config: config),
            lookup: [:],
            digests: try! ConfigLimitedSizeArray(config: config, defaultValue: WorkDigest.dummy(config: config)),
            authGasUsed: 0
        )
    }
}

extension WorkReport: Hashable32 {
    public func hash() -> Data32 {
        try! JamEncoder.encode(self).blake2b256hash()
    }
}

extension WorkReport: Validate {
    public enum WorkReportError: Swift.Error {
        case tooBig
        case invalidCoreIndex
        case tooManyDependencies
    }

    public func validate(config: Config) throws(WorkReportError) {
        guard refinementContext.prerequisiteWorkPackages.count + lookup.count <= config.value.maxDepsInWorkReport else {
            throw .tooManyDependencies
        }
        let resultBlobSize = digests.compactMap { digest in try? digest.result.result.get() }.reduce(0) { $0 + $1.count }
        guard authorizerTrace.count + resultBlobSize <= config.value.maxWorkReportBlobSize else {
            throw .tooBig
        }
        guard coreIndex < UInt32(config.value.totalNumberOfCores) else {
            throw .invalidCoreIndex
        }
    }
}
