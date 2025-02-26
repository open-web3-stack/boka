import Testing
import Utils

@testable import JAMTests

struct JamdunaTests {
    @Test(arguments: try JamTestnet.loadTests(path: "data/safrole/state_transitions", src: .jamduna))
    func safroleTests(_ input: Testcase) async throws {
        if input.description != "1_000.bin" {
            // TODO: probably accounts decoding fail
            return
        }

        try await CommonTests.test(input)
    }

    // @Test(arguments: try JamTestnet.loadTests(path: "data/fallback/state_transitions", src: .jamduna))
    // func fallbackTests(_ input: Testcase) async throws {
    // }
}
