import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif

final class QuicServerTests {
    @Test func start() throws {
        let quicServer = try QuicServer()
        #expect(throws: QuicError.self) {
            try quicServer.start(ipAddress: "127.0.0.1", port: 4567)
        }
        print("start Deinit")
    }
}
