import Testing
import Utils

@testable import JAMTests

struct JamdunaTests {
    @Test(arguments: try JamTestnet.loadTests(path: "data/generic/state_transitions", src: .jamduna))
    func genericTests(_ input: Testcase) async throws {
        await withKnownIssue("TODO: debug", isIntermittent: true) {
            try await TraceTest.test(input)
        }
    }

    @Test(arguments: try JamTestnet.loadTests(path: "data/assurances/state_transitions", src: .jamduna))
    func assurancesTests(_ input: Testcase) async throws {
        await withKnownIssue("TODO: debug", isIntermittent: true) {
            _ = try await TraceTest.test(input)
        }
    }

    @Test(arguments: try JamTestnet.loadTests(path: "data/orderedaccumulation/state_transitions", src: .jamduna))
    func orderedaccumulationTests(_ input: Testcase) async throws {
        await withKnownIssue("TODO: debug", isIntermittent: true) {
            _ = try await TraceTest.test(input)
        }
    }
}
