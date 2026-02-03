import Foundation
@testable import PolkaVM
import Testing
import Utils

// MARK: - Multi-Mode PVM Test Result

/// Result of executing a PVM program in a specific mode
struct PVMTestResult {
    let exitReason: ExitReason
    let finalGas: Gas
    let outputData: Data?
    let finalRegisters: Registers
    let finalPC: UInt32
    let mode: PVMExecutionMode
}

// MARK: - Multi-Mode PVM Test Executor

/// Helper struct for executing PVM tests in multiple modes
enum MultiModePVMTest {
    /// Execute a PVM program and capture detailed state
    ///
    /// - Parameters:
    ///   - mode: Execution mode to use
    ///   - blob: Program blob data
    ///   - pc: Initial program counter
    ///   - gas: Initial gas limit
    ///   - argumentData: Optional argument data to pass to program
    ///   - config: PVM configuration (uses default if not specified)
    ///   - context: Optional invocation context for host calls
    /// - Returns: PVMTestResult with execution details
    static func execute(
        mode: PVMExecutionMode,
        blob: Data,
        pc: UInt32 = 0,
        gas: Gas = Gas(1_000_000),
        argumentData: Data? = nil,
        config: PvmConfig = DefaultPvmConfig(),
        context: (any InvocationContext)? = nil,
    ) async -> PVMTestResult {
        // Execute the program
        let (exitReason, gasUsed, outputData) = await invokePVM(
            config: config,
            executionMode: mode.executionMode,
            blob: blob,
            pc: pc,
            gas: gas,
            argumentData: argumentData,
            ctx: context,
        )

        // Calculate final gas
        let finalGas = gas - gasUsed

        // For interpreter mode, we can capture additional state
        // Note: This requires re-execution to capture state, which is not ideal
        // but necessary for detailed state comparison
        let (finalRegisters, finalPC): (Registers, UInt32)

        if mode == .interpreter {
            // Re-run in interpreter mode to capture final state
            do {
                let state = try VMStateInterpreter(
                    standardProgramBlob: blob,
                    pc: pc,
                    gas: gas,
                    argumentData: argumentData,
                )
                let engine = Engine(config: config, invocationContext: context)
                _ = await engine.execute(state: state)
                finalRegisters = state.getRegisters()
                finalPC = state.pc
            } catch {
                // If re-execution fails, use empty values
                finalRegisters = Registers()
                finalPC = 0
            }
        } else {
            // Sandbox mode doesn't expose internal state the same way
            // Use empty values
            finalRegisters = Registers()
            finalPC = 0
        }

        return PVMTestResult(
            exitReason: exitReason,
            finalGas: finalGas,
            outputData: outputData,
            finalRegisters: finalRegisters,
            finalPC: finalPC,
            mode: mode,
        )
    }

    /// Execute a PVM program with explicit initial state (for low-level testing)
    ///
    /// - Parameters:
    ///   - mode: Execution mode to use
    ///   - program: Program code
    ///   - pc: Initial program counter
    ///   - gas: Initial gas
    ///   - memory: Initial memory state
    ///   - registers: Initial register values
    ///   - config: PVM configuration
    /// - Returns: Tuple of exit reason and final VM state (interpreter mode only)
    static func executeWithState(
        mode: PVMExecutionMode,
        program: ProgramCode,
        pc: UInt32,
        gas: Gas,
        memory: GeneralMemory,
        registers: Registers,
        config: PvmConfig = DefaultPvmConfig(),
    ) async -> (exitReason: ExitReason, finalState: VMStateInterpreter?) {
        // Only interpreter mode supports direct state manipulation
        guard mode == .interpreter else {
            // For sandbox mode, we'd need to serialize state to blob format
            // which is not straightforward for low-level testing
            return (.panic(.trap), nil)
        }

        let vmState = VMStateInterpreter(
            program: program,
            pc: pc,
            registers: registers,
            gas: gas,
            memory: memory,
        )

        let engine = Engine(config: config)
        let exitReason = await engine.execute(state: vmState)

        return (exitReason, vmState)
    }

    /// Compare results from two execution modes for parity
    ///
    /// - Parameters:
    ///   - result1: Result from first execution mode
    ///   - result2: Result from second execution mode
    ///   - compareState: Whether to compare register/PC state (default: false)
    /// - Returns: Description of differences, or nil if results match
    static func compareResults(
        _ result1: PVMTestResult,
        _ result2: PVMTestResult,
        compareState: Bool = false,
    ) -> String? {
        var differences: [String] = []

        // Compare exit reasons
        if result1.exitReason != result2.exitReason {
            differences.append(
                "Exit reason mismatch: \(result1.mode)=\(result1.exitReason) vs \(result2.mode)=\(result2.exitReason)",
            )
        }

        // Compare gas consumption (allow small differences for mode overhead)
        let gasDiff = abs(Int64(result1.finalGas.value) - Int64(result2.finalGas.value))
        if gasDiff > 10 {
            differences.append(
                "Gas mismatch: \(result1.mode)=\(result1.finalGas) vs \(result2.mode)=\(result2.finalGas) (diff: \(gasDiff))",
            )
        }

        // Compare output data
        if result1.outputData != result2.outputData {
            differences.append(
                "Output mismatch: \(result1.mode)=\(result1.outputData?.toHexString() ?? "nil") vs \(result2.mode)=\(result2.outputData?.toHexString() ?? "nil")",
            )
        }

        // Compare state if requested
        if compareState {
            if result1.finalRegisters != result2.finalRegisters {
                differences.append(
                    "Registers mismatch: \(result1.mode)=\(result1.finalRegisters) vs \(result2.mode)=\(result2.finalRegisters)",
                )
            }

            if result1.finalPC != result2.finalPC {
                differences.append(
                    "PC mismatch: \(result1.mode)=\(result1.finalPC) vs \(result2.mode)=\(result2.finalPC)",
                )
            }
        }

        return differences.isEmpty ? nil : differences.joined(separator: "; ")
    }
}
