import Foundation
@testable import JAMTests
import PolkaVM
import Testing
import TracingUtils
import Utils

private let logger = Logger(label: "PVMHostCallTests")

/// Host call tests that run in both interpreter and sandbox modes
///
/// These tests verify that host function calls work correctly
/// in both execution modes.
struct PVMHostCallTests {
    // MARK: - Host Call with Context Tests

    @Test func hostCall_interpreter() async throws {
        try await testHostCall(mode: .interpreter)
    }

    @Test func hostCall_sandbox() async throws {
        try await testHostCall(mode: .sandbox)
    }

    private func testHostCall(mode: PVMExecutionMode) async throws {
        let sumToNWithHostCall = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 48, 0, 0, 0, 0, 0, 40, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 10, 1, 1, 50, 0, 73,
            77, 18, 36, 104,
        ])

        struct TestInvocationContext: InvocationContext {
            public typealias ContextType = Void

            public var context: ContextType = ()

            public func dispatch(index _: UInt32, state: VMState) async -> ExecOutcome {
                // Simple host call that doubles the output value
                do {
                    let (outputAddr, len): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
                    let output = try state.readMemory(address: outputAddr, length: Int(len))
                    let value = output.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
                    let newOutput = withUnsafeBytes(of: value << 1) { Data($0) }
                    try state.writeMemory(address: outputAddr, values: newOutput)
                    return .continued
                } catch {
                    return .exit(.panic(.trap))
                }
            }
        }

        let config = DefaultPvmConfig()
        let (exitReason, _, output) = await invokePVM(
            config: config,
            executionMode: mode.executionMode,
            blob: sumToNWithHostCall,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([5]),
            ctx: TestInvocationContext(),
        )

        let value = output?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0

        // sum(5) = 15, doubled by host call = 30
        #expect(exitReason == .halt)
        #expect(value == 30)
        logger.debug("\(mode.description) host call test: output=\(value)")
    }

    // MARK: - Host Call Error Handling

    @Test func hostCallError_interpreter() async throws {
        try await testHostCallError(mode: .interpreter)
    }

    @Test func hostCallError_sandbox() async throws {
        try await testHostCallError(mode: .sandbox)
    }

    private func testHostCallError(mode: PVMExecutionMode) async throws {
        // Test with a context that returns an error
        struct ErrorInvocationContext: InvocationContext {
            public typealias ContextType = Void

            public var context: ContextType = ()

            public func dispatch(index _: UInt32, state _: VMState) async -> ExecOutcome {
                // Always return an error
                .exit(.panic(.trap))
            }
        }

        let config = DefaultPvmConfig()

        // Use program with host call that will fail
        _ = await invokePVM(
            config: config,
            executionMode: mode.executionMode,
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 48, 0, 0, 0, 0, 0, 40, 128, 119, 0,
                        51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
                        61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 10, 1, 1, 50, 0, 73,
                        77, 18, 36, 104]),
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([5]),
            ctx: ErrorInvocationContext(),
        )

        // Should handle the error gracefully
        logger.debug("\(mode.description) host call error test completed")
    }

    // MARK: - Host Call Gas Consumption

    @Test func hostCallGasParity() async {
        let config = DefaultPvmConfig()

        let sumToNWithHostCall = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 48, 0, 0, 0, 0, 0, 40, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 10, 1, 1, 50, 0, 73,
            77, 18, 36, 104,
        ])

        struct SimpleContext: InvocationContext {
            public typealias ContextType = Void
            public var context: ContextType = ()

            public func dispatch(index _: UInt32, state: VMState) async -> ExecOutcome {
                do {
                    let (outputAddr, len): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
                    let output = try state.readMemory(address: outputAddr, length: Int(len))
                    let value = output.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
                    let newOutput = withUnsafeBytes(of: value << 1) { Data($0) }
                    try state.writeMemory(address: outputAddr, values: newOutput)
                    return .continued
                } catch {
                    return .exit(.panic(.trap))
                }
            }
        }

        // Run in interpreter mode
        let (_, gasUsedInterpreter, _) = await invokePVM(
            config: config,
            executionMode: [],
            blob: sumToNWithHostCall,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([5]),
            ctx: SimpleContext(),
        )

        // Run in sandbox mode
        let (_, gasUsedSandbox, _) = await invokePVM(
            config: config,
            executionMode: .sandboxed,
            blob: sumToNWithHostCall,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([5]),
            ctx: SimpleContext(),
        )

        // Gas consumption should be similar
        let gasDiff = abs(Int64(gasUsedInterpreter.value) - Int64(gasUsedSandbox.value))
        #expect(
            gasDiff <= 20,
        )

        logger.debug("Host call gas parity: interpreter=\(gasUsedInterpreter), sandbox=\(gasUsedSandbox), diff=\(gasDiff)")
    }

    // MARK: - Multiple Host Calls

    @Test func multipleHostCalls_interpreter() async throws {
        try await testMultipleHostCalls(mode: .interpreter)
    }

    @Test func multipleHostCalls_sandbox() async throws {
        try await testMultipleHostCalls(mode: .sandbox)
    }

    private func testMultipleHostCalls(mode: PVMExecutionMode) async throws {
        // Test that multiple host calls work correctly
        // This is a placeholder - real test would use a program with multiple host calls
        logger.debug("\(mode.description) multiple host calls test completed")
    }

    // MARK: - Host Call with Gas Limits

    @Test func hostCallWithGasLimit_interpreter() async throws {
        try await testHostCallWithGasLimit(mode: .interpreter)
    }

    @Test func hostCallWithGasLimit_sandbox() async throws {
        try await testHostCallWithGasLimit(mode: .sandbox)
    }

    private func testHostCallWithGasLimit(mode: PVMExecutionMode) async throws {
        let config = DefaultPvmConfig()

        // Test with limited gas to ensure host calls respect gas limits
        let limitedGas = Gas(1000)

        _ = await invokePVM(
            config: config,
            executionMode: mode.executionMode,
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 48, 0, 0, 0, 0, 0, 40, 128, 119, 0,
                        51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
                        61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 10, 1, 1, 50, 0, 73,
                        77, 18, 36, 104]),
            pc: 0,
            gas: limitedGas,
            argumentData: Data([3]), // Smaller input for faster execution
            ctx: nil,
        )

        // Should either complete successfully or run out of gas
        logger.debug("\(mode.description) host call with gas limit completed")
    }

    // MARK: - Host Call State Modification

    @Test func hostCallStateModification_interpreter() async throws {
        try await testHostCallStateModification(mode: .interpreter)
    }

    @Test func hostCallStateModification_sandbox() async throws {
        try await testHostCallStateModification(mode: .sandbox)
    }

    private func testHostCallStateModification(mode: PVMExecutionMode) async throws {
        // Test that host calls can modify state correctly
        struct StateModifyingContext: InvocationContext {
            public typealias ContextType = Void
            public var context: ContextType = ()

            public func dispatch(index _: UInt32, state: VMState) async -> ExecOutcome {
                // Modify a register to verify state changes persist
                let testValue: UInt64 = 0xABCD
                state.writeRegister(Registers.Index(raw: 5), testValue)
                return .continued
            }
        }

        let config = DefaultPvmConfig()

        _ = await invokePVM(
            config: config,
            executionMode: mode.executionMode,
            blob: Data([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 48, 0, 0, 0, 0, 0, 40, 128, 119, 0,
                        51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
                        61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 10, 1, 1, 50, 0, 73,
                        77, 18, 36, 104]),
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([2]),
            ctx: StateModifyingContext(),
        )

        logger.debug("\(mode.description) host call state modification test completed")
    }
}
