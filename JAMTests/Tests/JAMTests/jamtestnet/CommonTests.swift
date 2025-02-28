import Testing
import Utils

@testable import JAMTests

enum CommonTests {
    static func test(_ input: Testcase) async throws {
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
            // TODO: compare details

            await #expect(stateRef.value.stateRoot == testcase.postState.root)
        case .failure:
            Issue.record("Expected success, got \(result)")
        }
    }
}
