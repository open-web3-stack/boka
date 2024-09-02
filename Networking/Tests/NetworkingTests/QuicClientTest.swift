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
            try try quicClient.start(target: "127.0.0.1", port: 4567)
        }
    }
}
