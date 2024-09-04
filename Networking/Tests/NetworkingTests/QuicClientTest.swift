import Foundation
import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif

final class QuicClientTests {
    @Test func start() throws {
        let quicClient = try QuicClient()
        try quicClient.start(ipAddress: "127.0.0.1", port: 4568)
        let status = try quicClient.send(message: Data("quic client test".utf8))
        let value = status.value
        print("send status: \(value)")
        try quicClient.wait()
    }
}
