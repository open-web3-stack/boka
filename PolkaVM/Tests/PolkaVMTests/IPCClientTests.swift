import Foundation
@testable import PolkaVM
import Testing

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

@Suite(.serialized)
struct IPCClientTests {
    @Test
    func executeRequestTimesOutWithoutResponse() async {
        #if os(macOS) || os(Linux)
            var sockets: [Int32] = [0, 0]
            let domain: Int32 = 1 // AF_UNIX
            let socketType: Int32 = 1 // SOCK_STREAM

            #if canImport(Glibc)
                let socketpairResult = Glibc.socketpair(domain, socketType, 0, &sockets)
            #elseif canImport(Darwin)
                let socketpairResult = Darwin.socketpair(domain, socketType, 0, &sockets)
            #endif

            guard socketpairResult == 0 else {
                Issue.record("Failed to create socketpair for timeout test")
                return
            }

            let clientFD = sockets[0]
            let peerFD = sockets[1]

            defer {
                #if canImport(Glibc)
                    _ = Glibc.close(clientFD)
                    _ = Glibc.close(peerFD)
                #elseif canImport(Darwin)
                    _ = Darwin.close(clientFD)
                    _ = Darwin.close(peerFD)
                #endif
            }

            let client = IPCClient(timeout: 0.2)
            client.setFileDescriptor(clientFD)

            do {
                _ = try await client.sendExecuteRequest(
                    blob: Data([0]),
                    pc: 0,
                    gas: 1,
                    argumentData: nil,
                    executionMode: .sandboxed,
                )
                Issue.record("Expected IPC timeout, but request unexpectedly succeeded")
            } catch IPCError.timeout {
                // Expected timeout path.
            } catch {
                Issue.record("Expected IPCError.timeout, got \(error)")
            }
        #else
            #expect(true)
        #endif
    }
}
