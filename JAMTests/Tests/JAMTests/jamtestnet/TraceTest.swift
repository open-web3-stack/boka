import Blockchain
import Codec
import Foundation
import Testing
import TracingUtils
import Utils

@testable import JAMTests

enum TraceTest {
    static func test(_ input: Testcase) async throws {
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
            #expect(stateRef.value.recentHistory.items == expectedState.recentHistory.items)
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

            // compare kv as well (so accounts are compared)
            let expectedStateDict = testcase.postState.toDict()
            for (key, value) in expectedStateDict {
                let ourVal = try await stateRef.value.read(key: key)
                #expect(
                    ourVal == value,
                    "kv mismatch for key: \(key), expected: \(value.toHexString()), got: \(ourVal?.toHexString() ?? "nil")"
                )
            }

            // root
            async #expect(stateRef.value.stateRoot == testcase.postState.root)
        case .failure:
            Issue.record("Expected success, got \(result)")
        }
    }
}
