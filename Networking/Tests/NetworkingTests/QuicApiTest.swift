import Testing

@testable import Networking

#if os(Linux)
// need to check
#elseif os(macOS)
    import CoreFoundation
    import Security
#endif

struct QuicApiTests {
    @Test func initialize() throws {
        #expect(try QuicApi() != nil)
    }
}
