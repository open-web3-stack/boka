import Testing
import Utils

@testable import JAMTests

enum CommonTests {
    static func test(_ input: Testcase) async throws {
        let testcase = try JamTestnet.decodeTestcase(input)

        // test state merklize function
        let preKv = testcase.preState.toKV()
        let postKv = testcase.postState.toKV()
        // TODO: fix state merkle fail
        #expect(try stateMerklize(kv: preKv) == testcase.preState.root, "pre_state root mismatch")
        #expect(try stateMerklize(kv: postKv) == testcase.postState.root, "post_state root mismatch")

        // test STF
        let result = try await JamTestnet.runSTF(testcase)
        switch result {
        case let .success(stateRef):
            await #expect(stateRef.value.stateRoot == testcase.postState.root)

        // TODO: compare details if root does not match
        // TODO: how to compare accounts stuff
        // #expect(stateRef.value == testcase.postState.toState(config: config))
        case .failure:
            Issue.record("Expected success, got \(result)")
        }
    }
}
