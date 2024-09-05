import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif

final class QuicServerTests {
    @Test func start() throws {
        // do {
        //     let server = try QuicServer()
        //     try server.start(ipAddress: "127.0.0.1", port: 4568)
        // } catch {
        //     print("Failed to start server: \(error)")
        // }
    }
}
