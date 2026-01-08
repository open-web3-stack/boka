import TracingUtils
import Utils

private let logger = Logger(label: "Authorization")

public enum AuthorizationError: Error {
    case invalidReportAuthorizer
    case emptyAuthorizationQueue
}

public struct AuthorizationPostState: Sendable, Equatable {
    public var coreAuthorizationPool: ConfigFixedSizeArray<
        ConfigLimitedSizeArray<
            Data32,
            ProtocolConfig.Int0,
            ProtocolConfig.MaxAuthorizationsPoolItems
        >,
        ProtocolConfig.TotalNumberOfCores
    >

    public init(
        coreAuthorizationPool: ConfigFixedSizeArray<
            ConfigLimitedSizeArray<
                Data32,
                ProtocolConfig.Int0,
                ProtocolConfig.MaxAuthorizationsPoolItems
            >,
            ProtocolConfig.TotalNumberOfCores
        >
    ) {
        self.coreAuthorizationPool = coreAuthorizationPool
    }
}

public protocol Authorization {
    var coreAuthorizationPool: ConfigFixedSizeArray<
        ConfigLimitedSizeArray<
            Data32,
            ProtocolConfig.Int0,
            ProtocolConfig.MaxAuthorizationsPoolItems
        >,
        ProtocolConfig.TotalNumberOfCores
    > { get }

    var authorizationQueue: ConfigFixedSizeArray<
        ConfigFixedSizeArray<
            Data32,
            ProtocolConfig.MaxAuthorizationsQueueItems
        >,
        ProtocolConfig.TotalNumberOfCores
    > { get }

    mutating func mergeWith(postState: AuthorizationPostState)
}

extension Authorization {
    public func update(
        config _: ProtocolConfigRef,
        timeslot: TimeslotIndex,
        auths: [(core: CoreIndex, auth: Data32)]
    ) throws -> AuthorizationPostState {
        var pool = coreAuthorizationPool

        // Create lookup for core authorizations
        let authsByCoreIndex = Dictionary(grouping: auths) { $0.core }

        for coreIndex in 0 ..< pool.count {
            var corePool = pool[coreIndex]
            let coreQueue = authorizationQueue[coreIndex]

            guard !coreQueue.isEmpty else {
                continue
            }

            let newItem = coreQueue[Int(timeslot) % coreQueue.count]

            // Remove used authorizers from pool
            try removeAuthorizers(from: &corePool, coreAuths: authsByCoreIndex[CoreIndex(coreIndex)])

            logger.trace("core index: \(coreIndex), newItem add to pool: \(newItem)")

            // Add new item from queue
            corePool.safeAppend(newItem)
            pool[coreIndex] = corePool
        }

        return AuthorizationPostState(coreAuthorizationPool: pool)
    }

    /// Remove used authorizers from the core pool
    ///
    /// - Parameters:
    ///   - corePool: The core pool to modify (inout)
    ///   - coreAuths: Optional array of (core, auth) tuples for this core
    /// - Throws: AuthorizationError.invalidReportAuthorizer if an auth is not found
    private func removeAuthorizers(
        from corePool: inout ConfigLimitedSizeArray<Data32, ProtocolConfig.Int0, ProtocolConfig.MaxAuthorizationsPoolItems>,
        coreAuths: [(core: CoreIndex, auth: Data32)]?
    ) throws {
        guard let coreAuths else {
            return
        }

        for (_, auth) in coreAuths {
            guard let idx = corePool.firstIndex(of: auth) else {
                throw AuthorizationError.invalidReportAuthorizer
            }
            _ = try corePool.remove(at: idx)
        }
    }
}
