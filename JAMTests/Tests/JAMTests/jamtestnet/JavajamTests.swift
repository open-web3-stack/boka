import Blockchain
import Testing

@testable import JAMTests

struct JavajamTests {
    @Test(arguments: try JamTestnet.loadTests(path: "state_transitions", src: .javajam))
    func allTests(_ input: Testcase) async throws {
        if input.description != "785461.bin" {
            return
        }

        try await CommonTests.test(input)
    }
}
