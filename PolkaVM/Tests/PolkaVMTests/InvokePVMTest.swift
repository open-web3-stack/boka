import Foundation
import Testing
import Utils

@testable import PolkaVM

// standard programs
let empty = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])
let fibonacci = Data([
    0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
    51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
    152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
    51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
])
let sumToN = Data([
    0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
    51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
    61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
    36, 24,
])
let sumToNWithHostCall = Data([
    0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 48, 0, 0, 0, 0, 0, 40, 128, 119, 0,
    51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
    61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 10, 1, 1, 50, 0, 73,
    77, 18, 36, 104,
])

struct InvokePVMTests {
    @Test func testEmptyProgram() async throws {
        let config = DefaultPvmConfig()
        let (exitReason, gas, output) = await invokePVM(
            config: config,
            blob: empty,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data(),
            ctx: nil
        )
        #expect(exitReason == .panic(.trap))
        #expect(gas == Gas(0))
        #expect(output == nil)
    }

    @Test(arguments: [
        (2, 2, 999_980),
        (8, 34, 999_944),
        (9, 55, 999_938),
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

    @Test(arguments: [
        (1, 1, 999_988),
        (4, 10, 999_979),
        (5, 15, 999_976),
    ])
    func testSumToN(testCase: (input: UInt8, output: UInt8, gas: UInt64)) async throws {
        let config = DefaultPvmConfig()
        let (exitReason, gas, output) = await invokePVM(
            config: config,
            blob: sumToN,
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

    @Test func testInvocationContext() async throws {
        let config = DefaultPvmConfig()

        struct TestInvocationContext: InvocationContext {
            public typealias ContextType = Void

            public var context: ContextType = ()

            public func dispatch(index _: UInt32, state: VMState) async -> ExecOutcome {
                // perform output * 2
                do {
                    let (ouputAddr, len): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
                    let output = try state.readMemory(address: ouputAddr, length: Int(len))
                    let value = output.withUnsafeBytes { $0.load(as: UInt32.self) }
                    let newOutput = withUnsafeBytes(of: value << 1) { Data($0) }
                    try state.writeMemory(address: ouputAddr, values: newOutput)
                    return .continued
                } catch {
                    return .exit(.panic(.trap))
                }
            }
        }

        let (exitReason, _, output) = await invokePVM(
            config: config,
            blob: sumToNWithHostCall,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([5]),
            ctx: TestInvocationContext()
        )

        let value = output?.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } ?? 0

        switch exitReason {
        case .halt:
            #expect(value == 30)
        default:
            Issue.record("Expected halt, got \(exitReason)")
        }
    }
}
