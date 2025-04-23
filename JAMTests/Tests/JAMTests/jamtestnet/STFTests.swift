import Foundation
import Testing
import TracingUtils
import Utils

@testable import JAMTests

enum STFTests {
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
            let expectedState = try testcase.postState.toState()
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

            // root
            async #expect(stateRef.value.stateRoot == testcase.postState.root)
        case .failure:
            Issue.record("Expected success, got \(result)")
        }
    }
}
