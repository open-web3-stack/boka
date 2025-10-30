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

    @Test(arguments: try JamTestnet.loadTests(path: "traces/storage_light", src: .w3f))
    func storageLightTests(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "traces/storage", src: .w3f))
    func storageTests(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "traces/preimages_light", src: .w3f))
    func preimagesLightTests(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "traces/preimages", src: .w3f))
    func preimagesTests(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "traces/fuzzy_light", src: .w3f))
    func fuzzyLightTests(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "traces/fuzzy", src: .w3f))
    func fuzzyTests(_ input: Testcase) async throws {
        try await TraceTest.test(input)
    }
}
