import Foundation
import Testing
import TracingUtils
import Utils

@testable import PolkaVM

// standard programs
let empty = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
// swiftformat:disable wrap wrapArguments
let fibonacci = Data(
    [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0, 51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200, 152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3]
)
// let sumThree

struct InvokePVMTests {
    init() {
        setupTestLogger()
    }

    @Test func testEmpty() async throws {}

    @Test(arguments: [
        // (0, 0),
        // (1, 1),
        // (2, 1),
        // (3, 2),
        // (4, 3),
        // (5, 5),
        // (6, 8),
        // (7, 13),
        // (8, 21),
        (9, 34, 999_938),
        // (10, 55, 999935),
    ])
    func testFibonacci(testCase: (input: UInt8, output: UInt8, gas: UInt64)) async throws {
        let config = DefaultPvmConfig()
        let (exitReason, gas, output) = await invokePVM(
            config: config,
            blob: fibonacci,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([testCase.input]),
            ctx: nil
        )

        let value = output?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0

        switch exitReason {
        case .halt:
            #expect(value == testCase.output)
            #expect(gas == Gas(testCase.gas))
        default:
            Issue.record("Expected halt, got \(exitReason)")
        }
    }

    @Test func testSumThree() async throws {}

    // TODO: add tests with a fake InvocationContext
}
