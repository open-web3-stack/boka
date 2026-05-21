@testable import Blockchain
import Foundation
import Testing
import Utils

struct AuthorizationRuntimeTests {
    private let config = ProtocolConfigRef.tiny

    @Test
    func updateRemovesUsedAuthorizersAndAppendsQueuedAuthorizers() throws {
        let state = try AuthorizationState(
            coreAuthorizationPool: makePool([[1, 2], [3]]),
            authorizationQueue: makeQueue(startingAt: 100),
        )

        let postState = try state.update(
            config: config,
            timeslot: 3,
            auths: [(core: 0, auth: data32(1))],
        )

        #expect(Array(postState.coreAuthorizationPool[0]) == [data32(2), data32(103)])
        #expect(Array(postState.coreAuthorizationPool[1]) == [data32(3), data32(104)])
    }

    @Test
    func updateRejectsAuthorizerMissingFromPool() throws {
        let state = try AuthorizationState(
            coreAuthorizationPool: makePool([[1, 2], [3]]),
            authorizationQueue: makeQueue(startingAt: 100),
        )

        #expect(throws: AuthorizationError.self) {
            _ = try state.update(
                config: config,
                timeslot: 3,
                auths: [(core: 0, auth: data32(99))],
            )
        }
    }

    private func makePool(
        _ values: [[UInt8]],
    ) throws -> ConfigFixedSizeArray<
        ConfigLimitedSizeArray<Data32, ProtocolConfig.Int0, ProtocolConfig.MaxAuthorizationsPoolItems>,
        ProtocolConfig.TotalNumberOfCores,
    > {
        let rows = try values.map { row in
            try ConfigLimitedSizeArray<
                Data32,
                ProtocolConfig.Int0,
                ProtocolConfig.MaxAuthorizationsPoolItems,
            >(config: config, array: row.map(data32))
        }
        return try ConfigFixedSizeArray(config: config, array: rows)
    }

    private func makeQueue(
        startingAt start: UInt8,
    ) throws -> ConfigFixedSizeArray<
        ConfigFixedSizeArray<Data32, ProtocolConfig.MaxAuthorizationsQueueItems>,
        ProtocolConfig.TotalNumberOfCores,
    > {
        let rows = try (0 ..< config.value.totalNumberOfCores).map { core in
            let items = (0 ..< config.value.maxAuthorizationsQueueItems).map { offset in
                data32(start + UInt8(core + offset))
            }
            return try ConfigFixedSizeArray<Data32, ProtocolConfig.MaxAuthorizationsQueueItems>(
                config: config,
                array: items,
            )
        }
        return try ConfigFixedSizeArray(config: config, array: rows)
    }
}

private struct AuthorizationState: Authorization {
    var coreAuthorizationPool: ConfigFixedSizeArray<
        ConfigLimitedSizeArray<Data32, ProtocolConfig.Int0, ProtocolConfig.MaxAuthorizationsPoolItems>,
        ProtocolConfig.TotalNumberOfCores,
    >
    var authorizationQueue: ConfigFixedSizeArray<
        ConfigFixedSizeArray<Data32, ProtocolConfig.MaxAuthorizationsQueueItems>,
        ProtocolConfig.TotalNumberOfCores,
    >

    mutating func mergeWith(postState: AuthorizationPostState) {
        coreAuthorizationPool = postState.coreAuthorizationPool
    }
}
