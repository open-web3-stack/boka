import Testing
import Utils

@testable import JAMTests

struct JamdunaTests {
    @Test(arguments: try JamTestnet.loadTests(path: "data/safrole/state_transitions", src: .jamduna))
    func safroleTests(_ input: Testcase) async throws {
        try await CommonTests.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "data/fallback/state_transitions", src: .jamduna))
    func fallbackTests(_ input: Testcase) async throws {
        try await CommonTests.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "data/orderedaccumulation/state_transitions", src: .jamduna))
    func orderedaccumulationTests(_ input: Testcase) async throws {
        await withKnownIssue("todo") {
            try await CommonTests.test(input)
        }
    }

    @Test(arguments: try JamTestnet.loadTests(path: "data/assurances/state_transitions", src: .jamduna))
    func assurancesTests(_ input: Testcase) async throws {
        await withKnownIssue("todo") {
            try await CommonTests.test(input)
        }
    }
}
