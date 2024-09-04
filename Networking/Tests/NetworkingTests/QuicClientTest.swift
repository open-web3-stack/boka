import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif

final class QuicClientTests {
    @Test func start() throws {
        let quicClient = try QuicClient()
        #expect(throws: QuicError.self) {
            try quicClient.start(ipAddress: "127.0.0.1", port: 4568)
        }
        print("start Deinit")
    }
}
