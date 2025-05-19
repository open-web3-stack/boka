import Codec
import Foundation
import Utils

// P
public struct WorkPackage: Comparable, Sendable, Equatable, Codable, Hashable {
    // j
    public var authorizationToken: Data

    // h
    public var authorizationServiceIndex: ServiceIndex

    // u
    public var authorizationCodeHash: Data32

    // p
    public var configurationBlob: Data

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
        configurationBlob: Data,
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
        self.configurationBlob = configurationBlob
        self.context = context
        self.workItems = workItems
    }

    public static func < (lhs: WorkPackage, rhs: WorkPackage) -> Bool {
        if lhs.authorizationServiceIndex != rhs.authorizationServiceIndex {
            return lhs.authorizationServiceIndex < rhs.authorizationServiceIndex
        }
        if lhs.authorizationCodeHash != rhs.authorizationCodeHash {
            return lhs.authorizationCodeHash < rhs.authorizationCodeHash
        }
        if lhs.context != rhs.context {
            return lhs.context < rhs.context
        }
        return lhs.workItems.count < rhs.workItems.count
    }
}

extension WorkPackage: Hashable32 {
    public func hash() -> Data32 {
        try! JamEncoder.encode(self).blake2b256hash()
    }
}

extension WorkPackage: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> WorkPackage {
        WorkPackage(
            authorizationToken: Data(),
            authorizationServiceIndex: 0,
            authorizationCodeHash: Data32(),
            configurationBlob: Data(),
            context: RefinementContext.dummy(config: config),
            workItems: try! ConfigLimitedSizeArray(config: config, defaultValue: WorkItem.dummy(config: config))
        )
    }
}

extension WorkPackage {
    public func encode() throws -> Data {
        try JamEncoder.encode(self)
    }

    public static func decode(data: Data, withConfig: ProtocolConfigRef) throws -> WorkPackage {
        try JamDecoder.decode(WorkPackage.self, from: data, withConfig: withConfig)
    }
}

extension WorkPackage {
    /// a: work-package’s implied authorizer, the hash of the concatenation of the authorization code
    /// and the configuration
    public func authorizer(serviceAccounts: some ServiceAccounts) async throws -> Data32? {
        guard let authorizationCode = try await authorizationCode(serviceAccounts: serviceAccounts) else {
            return nil
        }
        return Blake2b256.hash(authorizationCode, configurationBlob)
    }

    /// c: the authorization code
    public func authorizationCode(serviceAccounts: some ServiceAccounts) async throws -> Data? {
        guard let preimage = try await serviceAccounts.historicalLookup(
            serviceAccount: authorizationServiceIndex,
            timeslot: context.lookupAnchor.timeslot,
            preimageHash: authorizationCodeHash
        ) else {
            return nil
        }
        return try CodeAndMeta(data: preimage).codeBlob
    }
}

extension WorkPackage {
    public func asRef() -> WorkPackageRef {
        WorkPackageRef(self)
    }
}

public typealias WorkPackageRef = RefWithHash<WorkPackage>
