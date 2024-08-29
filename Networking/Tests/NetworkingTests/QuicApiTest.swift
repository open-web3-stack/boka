@testable import Networking
import Testing
#if os(Linux)
// need to check
#elseif os(macOS)
    import CoreFoundation
    import Security
#endif

@Test func initialize() throws {
    let quicApi = try QuicApi()
    #expect(quicApi.api != nil)
}
