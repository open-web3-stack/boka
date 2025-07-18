import Testing
import Utils

@testable import JAMTests

struct PolkajamTests {
    @Test(arguments: try JamTestnet.loadTests(path: "traces/fallback", src: .w3f))
    func fallbackTests(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "traces/safrole", src: .w3f))
    func safroleTests(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "traces/reports-l0", src: .w3f))
    func reportsl0Tests(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "traces/reports-l1", src: .w3f))
    func reportsl1Tests(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }
}
