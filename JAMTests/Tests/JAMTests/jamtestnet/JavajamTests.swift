import Blockchain
import Testing

@testable import JAMTests

struct JavajamTests {
    @Test(arguments: try JamTestnet.loadTests(path: "stf/state_transitions", src: .javajam))
    func allTests(_ input: Testcase) async throws {
        try await CommonTests.test(input)
    }
}
