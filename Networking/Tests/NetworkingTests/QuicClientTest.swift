import Foundation
import Testing

@testable import Networking

#if os(macOS)
    import CoreFoundation
    import Security
#endif

final class QuicClientTests {
    @Test func start() async throws {
        do {
            let quicClient = try QuicClient()
            let status = try await quicClient.start(ipAddress: "127.0.0.1", port: 4568)
            print(status)
        } catch {
            print("Failed to start quic client: \(error)")
        }
    }
}
