import Foundation
import PolkaVM
import Testing
import Utils

@Suite(.serialized)
struct RealJITSandboxTest {
    let config = DefaultPvmConfig()

    // Use the halt program which should work
    let haltProgram = Data([
        1, // 1 jump table entry
        0, 0, 0, 0, 0, 0, 0, 0, // jump table entry 0: offset 0
        0x01, // halt instruction (opcode 1)
    ])

    let iterations = 100

    @Test("REAL TEST: JIT vs JIT+Sandbox")
    func testRealJITSandbox() async throws {
        print("\n=== REAL JIT + SANDBOX TEST ===")
        print("Iterations: \(iterations)")

        // Test 1: Plain JIT
        print("\n1. JIT mode...")
        let start1 = Date()
        for _ in 0 ..< iterations {
            _ = await invokePVM(
                config: config,
                executionMode: .jit,
                blob: haltProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: nil,
                ctx: nil
            )
        }
        let time1 = Date().timeIntervalSince(start1) * 1000
        print("   Time: \(Int(time1))ms (\(Int(time1 / Double(iterations) * 1000))μs/exec)")

        // Test 2: JIT + Sandbox (THIS SHOULD WORK!)
        print("\n2. JIT + Sandbox mode...")
        let start2 = Date()
        for _ in 0 ..< iterations {
            _ = await invokePVM(
                config: config,
                executionMode: [.jit, .sandboxed],
                blob: haltProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: nil,
                ctx: nil
            )
        }
        let time2 = Date().timeIntervalSince(start2) * 1000
        print("   Time: \(Int(time2))ms (\(Int(time2 / Double(iterations) * 1000))μs/exec)")

        // Results
        print("\n=== RESULTS ===")
        print("JIT:           \(Int(time1))ms (baseline)")
        print("JIT + Sandbox: \(Int(time2))ms (\(Int((time2 - time1) / time1 * 100))% overhead)")

        if time2 < time1 * 1.5 {
            print("\n✅ Sandbox overhead is reasonable!")
        } else {
            print("\n⚠️  High overhead - this might be expected for simple programs")
        }
    }
}
