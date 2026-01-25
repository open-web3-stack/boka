import Foundation
import PolkaVM
import Testing
import TracingUtils
import Utils

@testable import JAMTests

private let logger = Logger(label: "PVMParityTests")

/// Comprehensive parity tests for PolkaVM execution modes
///
/// These tests verify that different execution backends (interpreter, JIT, sandboxed)
/// produce identical results for the same program input.
struct PVMParityTests {
    static func loadTests() throws -> [Testcase] {
        try TestLoader.getTestcases(path: "pvm/programs", extension: "json")
    }

    /// Execute a single test case with a specific execution mode
    static func executeTest(
        _ testCase: Testcase,
        executionMode: ExecutionMode,
        config: some PvmConfig = DefaultPvmConfig()
    ) async throws -> (
        status: Status,
        registers: Registers,
        pc: UInt32,
        gas: Gas,
        memory: [UInt32: [UInt8]],
        pageFaultAddress: UInt32?
    ) {
        let decoder = JSONDecoder()
        let testCase = try decoder.decode(PolkaVMTestcase.self, from: testCase.data)
        let program = try ProgramCode(Data(testCase.program))
        let memory = try GeneralMemory(
            pageMap: testCase.initialPageMap.map { (address: $0.address, length: $0.length, writable: $0.isWritable) },
            chunks: testCase.initialMemory.map { (address: $0.address, data: Data($0.contents)) }
        )

        let executor = Executor(mode: executionMode, config: config)
        let result = await executor.execute(
            blob: Data(testCase.program),
            pc: testCase.initialPC,
            gas: testCase.initialGas,
            argumentData: nil,
            ctx: nil
        )

        // Determine status
        let status: Status
        let pageFaultAddress: UInt32?
        switch result.exitReason {
        case .halt:
            status = .halt
            pageFaultAddress = nil
        case let .pageFault(addr):
            status = .pageFault
            pageFaultAddress = addr
        default:
            status = .panic
            pageFaultAddress = nil
        }

        // Collect memory state
        var memoryState: [UInt32: [UInt8]] = [:]
        for chunk in testCase.initialMemory {
            var data: [UInt8] = []
            for offset in 0 ..< chunk.contents.count {
                if let value = try? result.finalMemory.read(address: chunk.address + UInt32(offset)) {
                    data.append(value)
                }
            }
            if !data.isEmpty {
                memoryState[chunk.address] = data
            }
        }

        return (
            status: status,
            registers: result.finalRegisters,
            pc: result.finalPC,
            gas: result.finalGas,
            memory: memoryState,
            pageFaultAddress: pageFaultAddress
        )
    }

    /// Compare two execution results for parity
    static func compareResults(
        _ result1: (
            status: Status,
            registers: Registers,
            pc: UInt32,
            gas: Gas,
            memory: [UInt32: [UInt8]],
            pageFaultAddress: UInt32?
        ),
        _ result2: (
            status: Status,
            registers: Registers,
            pc: UInt32,
            gas: Gas,
            memory: [UInt32: [UInt8]],
            pageFaultAddress: UInt32?
        ),
        testName: String
    ) {
        #expect(result1.status == result2.status, "\(testName): Status mismatch - \(result1.status) vs \(result2.status)")
        #expect(result1.registers == result2.registers, "\(testName): Registers mismatch")
        #expect(result1.pc == result2.pc, "\(testName): PC mismatch - \(result1.pc) vs \(result2.pc)")
        #expect(result1.pageFaultAddress == result2.pageFaultAddress, "\(testName): Page fault address mismatch")

        // Gas should be identical
        #expect(result1.gas == result2.gas, "\(testName): Gas mismatch - \(result1.gas) vs \(result2.gas)")

        // Compare memory for addresses that were initialized
        for (address, data1) in result1.memory {
            if let data2 = result2.memory[address] {
                #expect(data1.count == data2.count, "\(testName): Memory size mismatch at \(address)")
                for (offset, byte1) in data1.enumerated() {
                    if offset < data2.count {
                        let byte2 = data2[offset]
                        #expect(byte1 == byte2, "\(testName): Memory mismatch at \(address + UInt32(offset)) - \(byte1) vs \(byte2)")
                    }
                }
            }
        }
    }

    // MARK: - Interpreter vs Sandbox Parity Tests

    @Testtry (arguments: loadTests())
    func interpreter_vs_sandbox(testCase: Testcase) async throws {
        do {
            let resultInterpreter = try await Self.executeTest(testCase, executionMode: [])
            let resultSandbox = try await Self.executeTest(testCase, executionMode: .sandboxed)

            Self.compareResults(resultInterpreter, resultSandbox, testName: testCase.description)
        } catch {
            // Log error but don't fail the test - some test cases may be invalid
            logger.warning("Test \(testCase.description) failed with error: \(error)")
            throw error
        }
    }
}
