import Foundation
@testable import PolkaVM
import Testing
import Utils

/// Unit tests for ExitReason
struct ExitReasonTests {
    @Test func exitReasonHalt() {
        let halt = ExitReason.halt
        #expect(halt == .halt)
    }

    @Test func exitReasonOutOfGas() {
        let outOfGas = ExitReason.outOfGas
        #expect(outOfGas == .outOfGas)
    }

    @Test func exitReasonPanic() {
        let trap = ExitReason.panic(.trap)
        #expect(trap == .panic(.trap))

        let invalidInstruction = ExitReason.panic(.invalidInstructionIndex)
        #expect(invalidInstruction == .panic(.invalidInstructionIndex))
    }

    @Test func exitReasonEquality() {
        let halt1 = ExitReason.halt
        let halt2 = ExitReason.halt
        let outOfGas = ExitReason.outOfGas

        #expect(halt1 == halt2)
        #expect(halt1 != outOfGas)
    }

    @Test func exitReasonSendable() {
        /// ExitReason should be Sendable
        func requiresSendable(_ _: some Sendable) {}
        requiresSendable(ExitReason.halt)
        requiresSendable(ExitReason.outOfGas)
        requiresSendable(ExitReason.panic(.trap))
    }

    @Test func allPanicReasons() {
        // Test various panic reasons
        let panicReasons: [ExitReason.PanicReason] = [
            .trap,
            .invalidInstructionIndex,
            .invalidDynamicJump,
            .invalidBranch,
        ]

        for reason in panicReasons {
            let exitReason = ExitReason.panic(reason)
            if case let .panic(r) = exitReason {
                #expect(r == reason)
            } else {
                Issue.record("Should be panic with reason \(reason)")
            }
        }
    }
}
