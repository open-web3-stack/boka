@testable import Blockchain
import Foundation
import Testing
import Utils

struct AccumulationMergeTests {
    private let config = ProtocolConfigRef.tiny

    @Test
    func delegatorCanDesignateWhenItChangesDelegatorInSameBatch() throws {
        var state = try makeAccumulateState(delegator: 0)
        let designatedQueue = try makeValidatorQueue(startingAt: 10)

        var outputState = state.copy()
        outputState.delegator = 7
        outputState.validatorQueue = designatedQueue

        State.mergePrivilegedUpdates(
            into: &state,
            from: [(0, makeResult(state: outputState))],
        )

        #expect(state.delegator == 7)
        #expect(state.validatorQueue == designatedQueue)
    }

    @Test
    func assignerHandoffDoesNotGrantAuthorityWithinSameBatch() throws {
        let initialAssigner: ServiceIndex = 1
        let nextAssigner: ServiceIndex = 100
        var state = try makeAccumulateState(assigners: [initialAssigner, 2])
        let acceptedQueue = try makeAuthorizationQueue(startingAt: 10)
        let rejectedQueue = try makeAuthorizationQueue(startingAt: 20)

        var initialAssignerOutput = state.copy()
        initialAssignerOutput.assigners[0] = nextAssigner
        initialAssignerOutput.authorizationQueue[0] = acceptedQueue[0]

        var nextAssignerOutput = state.copy()
        nextAssignerOutput.authorizationQueue[0] = rejectedQueue[0]

        State.mergePrivilegedUpdates(
            into: &state,
            from: [
                (initialAssigner, makeResult(state: initialAssignerOutput)),
                (nextAssigner, makeResult(state: nextAssignerOutput)),
            ],
        )

        #expect(state.assigners[0] == nextAssigner)
        #expect(state.authorizationQueue[0] == acceptedQueue[0])
    }

    private func makeAccumulateState(
        assigners: [ServiceIndex]? = nil,
        delegator: ServiceIndex = 0,
    ) throws -> AccumulateState {
        let baseState = State.dummy(config: config)
        let assignerValues = assigners ?? Array(repeating: ServiceIndex(0), count: config.value.totalNumberOfCores)

        return AccumulateState(
            accounts: ServiceAccountsMutRef(baseState),
            validatorQueue: try makeValidatorQueue(startingAt: 1),
            authorizationQueue: try makeAuthorizationQueue(startingAt: 1),
            manager: 0,
            assigners: try ConfigFixedSizeArray(config: config, array: assignerValues),
            delegator: delegator,
            registrar: 0,
            alwaysAcc: [:],
            entropy: Data32(),
        )
    }

    private func makeResult(state: AccumulateState) -> AccumulationResult {
        AccumulationResult(
            state: state,
            transfers: [],
            commitment: nil,
            gasUsed: Gas(0),
            provide: [],
        )
    }

    private func makeValidatorQueue(
        startingAt start: UInt8,
    ) throws -> ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators> {
        let validators = try (0 ..< config.value.totalNumberOfValidators).map {
            try ValidatorKey(data: Data(repeating: start + UInt8($0), count: 336))
        }
        return try ConfigFixedSizeArray(config: config, array: validators)
    }

    private func makeAuthorizationQueue(
        startingAt start: UInt8,
    ) throws -> ConfigFixedSizeArray<
        ConfigFixedSizeArray<Data32, ProtocolConfig.MaxAuthorizationsQueueItems>,
        ProtocolConfig.TotalNumberOfCores
    > {
        let queues = try (0 ..< config.value.totalNumberOfCores).map { core in
            let items = (0 ..< config.value.maxAuthorizationsQueueItems).map {
                Data32(Data(repeating: start + UInt8(core + $0), count: 32))!
            }
            return try ConfigFixedSizeArray<Data32, ProtocolConfig.MaxAuthorizationsQueueItems>(
                config: config,
                array: items,
            )
        }

        return try ConfigFixedSizeArray(config: config, array: queues)
    }
}
