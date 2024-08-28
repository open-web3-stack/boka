@testable import Networking
import Testing
#if os(Linux)
//
#elseif os(macOS)
    import CoreFoundation
    import Security
#endif
@Test func example() async throws {
    #expect(msquicInit() == 1)
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
}
