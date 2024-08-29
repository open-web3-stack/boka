import Testing
#if os(Linux)
// need to check
#elseif os(macOS)
    import CoreFoundation
    import Security
#endif

@testable import Networking

final class QuicApiTests {
    @Test func initialize() throws {
        #expect(try QuicApi() != nil)
    }
}
