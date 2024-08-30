import Testing
#if os(macOS)
    import CoreFoundation
    import Security
#endif

@testable import Networking

final class QuicClientTests {
    @Test func start() throws {
        let quicClient = try QuicClient()
        try quicClient.start(target: "127.0.0.1", port: 4567)
    }
}
