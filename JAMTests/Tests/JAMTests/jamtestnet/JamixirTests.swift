import Testing
import Utils

@testable import JAMTests

struct JamixirTests {
    @Test(arguments: try JamTestnet.loadTests(path: "data/fallback/state_transitions", src: .jamixir))
    func fallbackTests(_ input: Testcase) async throws {
        if input.description != "1_000.bin" {
            return
        }
        try await CommonTests.test(input)
    }
}
