import Foundation
@testable import JAMTests
@testable import PolkaVM
import Testing
import Utils

/// PVM standard-program interpreter smoke tests.
struct PVMMultiModeTests {
    @Test func sumToN_interpreter() async throws {
        let sumToN = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        let (exitReason, _, output) = await invokePVM(
            config: DefaultPvmConfig(),
            executionMode: [],
            blob: sumToN,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([5]),
            ctx: nil,
        )

        let value = output?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0
        #expect(exitReason == .halt)
        #expect(value == 15)
    }

    @Test func fibonacci_interpreter() async throws {
        let fibonacci = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
            51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
            152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
            51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
        ])

        let (exitReason, _, output) = await invokePVM(
            config: DefaultPvmConfig(),
            executionMode: [],
            blob: fibonacci,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([8]),
            ctx: nil,
        )

        let value = output?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0
        #expect(exitReason == .halt)
        #expect(value == 34)
    }

    @Test func emptyProgram_interpreter() async throws {
        let empty = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])

        let (exitReason, _, output) = await invokePVM(
            config: DefaultPvmConfig(),
            executionMode: [],
            blob: empty,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data(),
            ctx: nil,
        )

        #expect(exitReason == .panic(.trap))
        #expect(output == nil)
    }
}
