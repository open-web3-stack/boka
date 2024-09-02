import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif

final class QuicClientTests {
    @Test func start() throws {
        let quicClient = try QuicClient()
//        try quicClient.start(target: "127.0.0.1", port: 4567)
        #expect(throws: QuicError.self) {
            try quicClient.start(target: "127.0.0.1", port: 4567)
        }
        print("start Deinit")
    }
}
