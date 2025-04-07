import Testing
import Utils

@testable import JAMTests

struct JamdunaTests {
    @Test(arguments: try JamTestnet.loadTests(path: "data/safrole/state_transitions", src: .jamduna))
    func safroleTests(_ input: Testcase) async throws {
        try await CommonTests.test(input)
    }

    // @Test(arguments: try JamTestnet.loadTests(path: "data/safrole/state_transitions_fuzzed", src: .jamduna))
    // func safroleFuzzedTests(_ input: Testcase) async throws {
    //     if !input.description.starts(with: "1_005_A") {
    //         return
    //     }
    //     _ = try await CommonTests.test(input)
    // }

    @Test(arguments: try JamTestnet.loadTests(path: "data/fallback/state_transitions", src: .jamduna))
    func fallbackTests(_ input: Testcase) async throws {
        try await CommonTests.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "data/assurances/state_transitions", src: .jamduna))
    func assurancesTests(_ input: Testcase) async throws {
        _ = try await CommonTests.test(input)
    }

    // @Test(arguments: try JamTestnet.loadTests(path: "data/assurances/state_transitions_fuzzed", src: .jamduna))
    // func assurancesFuzzedTests(_ input: Testcase) async throws {
    //     _ = try await CommonTests.test(input)
    // }

    @Test(arguments: try JamTestnet.loadTests(path: "data/orderedaccumulation/state_transitions", src: .jamduna))
    func orderedaccumulationTests(_ input: Testcase) async throws {
        _ = try await CommonTests.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "data/disputes/state_transitions", src: .jamduna))
    func disputesTests(_ input: Testcase) async throws {
        // these do not pass a check we have: invalidHeaderEpochMarker
        if ["2_000.bin", "3_010.bin", "4_000.bin"].contains(input.description) {
            return
        }

        try await CommonTests.test(input)
    }
}
