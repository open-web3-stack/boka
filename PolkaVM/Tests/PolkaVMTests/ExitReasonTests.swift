import Foundation
@testable import PolkaVM
import Testing
import Utils

/// Unit tests for ExitReason
struct ExitReasonTests {
    @Test func exitReasonHalt() {
        let halt = ExitReason.halt
        switch halt {
        case .halt:
            #expect(true)
        default:
            #expect(false, "Should be halt")
        }
    }

    @Test func exitReasonOutOfGas() {
        let outOfGas = ExitReason.outOfGas
        switch outOfGas {
        case .outOfGas:
            #expect(true)
        default:
            #expect(false, "Should be outOfGas")
        }
    }

    @Test func exitReasonPanic() {
        let trap = ExitReason.panic(.trap)
        switch trap {
        case .panic(.trap):
            #expect(true)
        default:
            #expect(false, "Should be panic trap")
        }

        let invalidInstruction = ExitReason.panic(.invalidInstructionIndex)
        switch invalidInstruction {
        case .panic(.invalidInstructionIndex):
            #expect(true)
        default:
            #expect(false, "Should be panic invalidInstructionIndex")
        }
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
            switch exitReason {
            case let .panic(r):
                #expect(r == reason)
            default:
                Issue.record("Should be panic with reason \(reason)")
            }
        }
    }
}
