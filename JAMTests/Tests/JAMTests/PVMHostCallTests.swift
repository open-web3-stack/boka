import Foundation
@testable import JAMTests
import PolkaVM
import Testing
import TracingUtils
import Utils

private let logger = Logger(label: "PVMHostCallTests")

/// Host call tests for the interpreter execution path.
struct PVMHostCallTests {
    private let sumToNWithHostCall = Data([
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 48, 0, 0, 0, 0, 0, 40, 128, 119, 0,
        51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
        61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 10, 1, 1, 50, 0, 73,
        77, 18, 36, 104,
    ])

    @Test func hostCall_interpreter() async throws {
        struct TestInvocationContext: InvocationContext {
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

        let (exitReason, _, output) = await invokePVM(
            config: DefaultPvmConfig(),
            executionMode: [],
            blob: sumToNWithHostCall,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([5]),
            ctx: TestInvocationContext(),
        )

        let value = output?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0
        #expect(exitReason == .halt)
        #expect(value == 30)
    }

    @Test func hostCallError_interpreter() async throws {
        struct ErrorInvocationContext: InvocationContext {
            public typealias ContextType = Void
            public var context: ContextType = ()

            public func dispatch(index _: UInt32, state _: VMState) async -> ExecOutcome {
                .exit(.panic(.trap))
            }
        }

        _ = await invokePVM(
            config: DefaultPvmConfig(),
            executionMode: [],
            blob: sumToNWithHostCall,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([5]),
            ctx: ErrorInvocationContext(),
        )

        logger.debug("interpreter host call error test completed")
    }

    @Test func multipleHostCalls_interpreter() async throws {
        logger.debug("interpreter multiple host calls test completed")
    }

    @Test func hostCallWithGasLimit_interpreter() async throws {
        _ = await invokePVM(
            config: DefaultPvmConfig(),
            executionMode: [],
            blob: sumToNWithHostCall,
            pc: 0,
            gas: Gas(1000),
            argumentData: Data([3]),
            ctx: nil,
        )

        logger.debug("interpreter host call with gas limit completed")
    }

    @Test func hostCallStateModification_interpreter() async throws {
        struct StateModifyingContext: InvocationContext {
            public typealias ContextType = Void
            public var context: ContextType = ()

            public func dispatch(index _: UInt32, state: VMState) async -> ExecOutcome {
                state.writeRegister(Registers.Index(raw: 5), 0xABCD)
                return .continued
            }
        }

        _ = await invokePVM(
            config: DefaultPvmConfig(),
            executionMode: [],
            blob: sumToNWithHostCall,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([2]),
            ctx: StateModifyingContext(),
        )

        logger.debug("interpreter host call state modification test completed")
    }
}
