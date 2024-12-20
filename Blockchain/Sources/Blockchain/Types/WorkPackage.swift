import Foundation
import Utils

// P
public struct WorkPackage: Sendable, Equatable, Codable {
    // j
    public var authorizationToken: Data

    // h
    public var authorizationServiceIndex: ServiceIndex

    // c
    public var authorizationCodeHash: Data32

    // p
    public var parameterizationBlob: Data

    // x
    public var context: RefinementContext

    // w
    public var workItems: ConfigLimitedSizeArray<
        WorkItem,
        ProtocolConfig.Int1,
        ProtocolConfig.MaxWorkItems
    >

    public init(
        authorizationToken: Data,
        authorizationServiceIndex: ServiceIndex,
        authorizationCodeHash: Data32,
        parameterizationBlob: Data,
        context: RefinementContext,
        workItems: ConfigLimitedSizeArray<
            WorkItem,
            ProtocolConfig.Int1,
            ProtocolConfig.MaxWorkItems
        >
    ) {
        self.authorizationToken = authorizationToken
        self.authorizationServiceIndex = authorizationServiceIndex
        self.authorizationCodeHash = authorizationCodeHash
        self.parameterizationBlob = parameterizationBlob
        self.context = context
        self.workItems = workItems
    }
}

extension WorkPackage: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> WorkPackage {
        WorkPackage(
            authorizationToken: Data(),
            authorizationServiceIndex: 0,
            authorizationCodeHash: Data32(),
            parameterizationBlob: Data(),
            context: RefinementContext.dummy(config: config),
            workItems: try! ConfigLimitedSizeArray(config: config, defaultValue: WorkItem.dummy(config: config))
        )
    }
}
