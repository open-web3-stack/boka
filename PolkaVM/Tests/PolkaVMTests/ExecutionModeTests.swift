import Foundation
@testable import PolkaVM
import Testing
import Utils

/// Unit tests for ExecutionMode and PVMExecutionMode
struct ExecutionModeTests {
    @Test func executionModeOptionSet() {
        // Test empty execution mode (interpreter)
        let interpreterMode = ExecutionMode()
        #expect(interpreterMode.rawValue == 0)

        // Test individual flags
        let jitMode = ExecutionMode.jit
        #expect(jitMode.rawValue == 1 << 0)

        let sandboxMode = ExecutionMode.sandboxed
        #expect(sandboxMode.rawValue == 1 << 1)

        // Test combination
        let jitSandboxMode: ExecutionMode = [.jit, .sandboxed]
        #expect(jitSandboxMode.rawValue == (1 << 0 | 1 << 1))
    }

    @Test func pVMExecutionModeEnum() {
        // Test interpreter mode
        let interpreter = PVMExecutionMode.interpreter
        #expect(interpreter.description == "interpreter")
        #expect(interpreter.executionMode.rawValue == 0)

        // Test sandbox mode
        let sandbox = PVMExecutionMode.sandbox
        #expect(sandbox.description == "sandbox")
        #expect(sandbox.executionMode == .sandboxed)

        // Test all cases
        #expect(PVMExecutionMode.allCases.count == 2)
        #expect(PVMExecutionMode.allCases.contains(.interpreter))
        #expect(PVMExecutionMode.allCases.contains(.sandbox))
    }

    @Test func executionModeSendable() {
        /// ExecutionMode should be Sendable
        func requiresSendable(_ _: some Sendable) {}
        requiresSendable(ExecutionMode())
        requiresSendable(PVMExecutionMode.interpreter)
    }
}
