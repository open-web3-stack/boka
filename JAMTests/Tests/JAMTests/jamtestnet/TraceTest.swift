import Blockchain
import Codec
import Foundation
import Testing
import TracingUtils
import Utils

@testable import JAMTests

private let logger = Logger(label: "TraceTest")

enum TraceTest {
    static func test(_ input: Testcase, allowFailure: Bool = false) async throws {
        // setupTestLogger()

        let testcase = try JamTestnet.decodeTestcase(input)

        // test state merklize
        let preKv = testcase.preState.toDict()
        let postKv = testcase.postState.toDict()
        #expect(try stateMerklize(kv: preKv) == testcase.preState.root, "pre_state root mismatch")
        #expect(try stateMerklize(kv: postKv) == testcase.postState.root, "post_state root mismatch")

        // test STF
        let result = try await JamTestnet.runSTF(testcase)
        switch result {
        case let .success(stateRef):
            let expectedState = try await testcase.postState.toState()
            // compare details
            #expect(stateRef.value.coreAuthorizationPool == expectedState.coreAuthorizationPool)
            #expect(stateRef.value.authorizationQueue == expectedState.authorizationQueue)
            #expect(stateRef.value.recentHistory == expectedState.recentHistory)
            #expect(stateRef.value.safroleState == expectedState.safroleState)
            #expect(stateRef.value.judgements == expectedState.judgements)
            #expect(stateRef.value.entropyPool == expectedState.entropyPool)
            #expect(stateRef.value.validatorQueue == expectedState.validatorQueue)
            #expect(stateRef.value.currentValidators == expectedState.currentValidators)
            #expect(stateRef.value.previousValidators == expectedState.previousValidators)
            #expect(stateRef.value.reports == expectedState.reports)
            #expect(stateRef.value.timeslot == expectedState.timeslot)
            #expect(stateRef.value.privilegedServices == expectedState.privilegedServices)
            #expect(stateRef.value.activityStatistics == expectedState.activityStatistics)
            #expect(stateRef.value.accumulationQueue == expectedState.accumulationQueue)
            #expect(stateRef.value.accumulationHistory == expectedState.accumulationHistory)
            #expect(stateRef.value.lastAccumulationOutputs == expectedState.lastAccumulationOutputs)

            // compare kv as well (so accounts are compared)
            let expectedStateDict = testcase.postState.toDict()
            for (key, value) in expectedStateDict {
                let ourVal = try await stateRef.value.read(key: key)
                #expect(
                    ourVal == value,
                    "kv mismatch for key: \(key), expected: \(value.toHexString()), got: \(ourVal?.toHexString() ?? "nil")"
                )
            }

            // make sure we don't have extra keys
            let allKeys = try await stateRef.value.backend.getKeys(nil, nil, nil)
            for (key, _) in allKeys {
                let data31 = Data31(key)!
                #expect(expectedStateDict[data31] != nil, "extra key in boka post state: \(data31.toHexString())")
            }

            let stateRoot = await stateRef.value.stateRoot
            #expect(stateRoot == testcase.postState.root)
        case .failure:
            if !allowFailure {
                Issue.record("Expected success, got \(result)")
            } else {
                logger.debug("STF failed with expected error: \(result)")
                #expect(testcase.preState.root == testcase.postState.root)
            }
        }
    }
}
