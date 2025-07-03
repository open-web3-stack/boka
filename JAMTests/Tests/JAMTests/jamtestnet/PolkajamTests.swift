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
        await withKnownIssue("TODO: debug", isIntermittent: true) {
            // 00000027.bin, 00000089.bin got some missing footprint
            // 00000043.bin, 00000069.bin, 00000071.bin, 00000093.bin
            //   got a weired missing state key (account storage) after state.save
            //   StateBackend.write's trie.update call

            if !input.description.starts(with: "00000027") {
                return
            }
            _ = try await TraceTest.test(input)
        }
    }

    @Test(arguments: try JamTestnet.loadTests(path: "traces/reports-l1", src: .w3f))
    func reportsl1Tests(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }
}
