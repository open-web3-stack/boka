import Foundation
@testable import PolkaVM
import Testing
import Utils

/// Unit tests for ExecutionMode
struct ExecutionModeTests {
    @Test func executionModeOptionSet() {
        let interpreterMode = ExecutionMode()
        #expect(interpreterMode.rawValue == 0)

        let jitMode = ExecutionMode.jit
        #expect(jitMode.rawValue == 1 << 0)
    }

    @Test func executionModeSendable() {
        /// ExecutionMode should be Sendable
        func requiresSendable(_ _: some Sendable) {}
        requiresSendable(ExecutionMode())
    }
}
