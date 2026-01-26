import Foundation
import PolkaVM
import Testing
import Utils

@Suite(.serialized)
struct JITSandboxPerformanceTests {
    let config = DefaultPvmConfig()

    // Sum integers program
    let sumToNProgram = Data([
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
        51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
        61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
        36, 24,
    ])

    let iterations = 200

    @Test("PROPER TEST: JIT vs Interpreter vs JIT+Sandbox")
    func properJITTest() async throws {
        print("\n=== REAL PERFORMANCE TEST: JIT vs Interpreter ===")
        print("Iterations: \(iterations)")

        // Test 1: Plain Interpreter (baseline)
        print("\n1. Interpreter mode...")
        let start1 = Date()
        for _ in 0 ..< iterations {
            _ = await invokePVM(
                config: config,
                executionMode: [],
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([25]),
                ctx: nil
            )
        }
        let time1 = Date().timeIntervalSince(start1) * 1000
        print("   Time: \(Int(time1))ms (\(Int(time1 / Double(iterations) * 1000))μs/exec)")

        // Test 2: JIT mode (THIS IS WHAT ACTUALLY MATTERS)
        print("\n2. JIT mode...")
        let start2 = Date()
        for _ in 0 ..< iterations {
            _ = await invokePVM(
                config: config,
                executionMode: .jit,
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([25]),
                ctx: nil
            )
        }
        let time2 = Date().timeIntervalSince(start2) * 1000
        print("   Time: \(Int(time2))ms (\(Int(time2 / Double(iterations) * 1000))μs/exec)")
        print("   Speedup vs Interpreter: \(String(format: "%.1fx", time1 / time2))")

        // Test 3: Sandbox (NOT JIT - for comparison)
        print("\n3. Sandbox mode (interpreter in process - WTF)...")
        let start3 = Date()
        for _ in 0 ..< iterations {
            _ = await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([25]),
                ctx: nil
            )
        }
        let time3 = Date().timeIntervalSince(start3) * 1000
        print("   Time: \(Int(time3))ms (\(Int(time3 / Double(iterations) * 1000))μs/exec)")
        print("   Overhead vs Interpreter: \(Int((time3 - time1) / time1 * 100))%")

        // Test 4: JIT + Sandbox (THE HOLY GRAIL)
        print("\n4. JIT + Sandbox mode (THIS IS WHAT WE WANT!)...")
        let start4 = Date()
        for _ in 0 ..< iterations {
            _ = await invokePVM(
                config: config,
                executionMode: [.jit, .sandboxed],
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([25]),
                ctx: nil
            )
        }
        let time4 = Date().timeIntervalSince(start4) * 1000
        print("   Time: \(Int(time4))ms (\(Int(time4 / Double(iterations) * 1000))μs/exec)")
        print("   Speedup vs Interpreter: \(String(format: "%.2fx", time1 / time4))")
        print("   Overhead vs pure JIT: \(Int((time4 - time2) / time2 * 100))%")

        // Summary
        print("\n" + String(repeating: "=", count: 60))
        print("SUMMARY")
        print(String(repeating: "=", count: 60))
        print("Interpreter:        \(Int(time1))ms (baseline)")
        print("JIT:                \(Int(time2))ms (\(String(format: "%.1fx", time1 / time2)) faster)")
        print("Sandbox (interp):   \(Int(time3))ms (\(Int((time3 - time1) / time1 * 100))% overhead)")
        print(
            "JIT + Sandbox:      \(Int(time4))ms (\(String(format: "%.2fx", time1 / time4)) faster, \(Int((time4 - time2) / time2 * 100))% overhead vs pure JIT)"
        )
        print(String(repeating: "=", count: 60))

        // Calculate the REAL benefit of JIT+Sandbox
        let jitSpeedup = time1 / time2
        let jitSandboxSpeedup = time1 / time4
        let sandboxOverheadOfJIT = (time4 - time2) / time2 * 100

        print("\n🚀 KEY FINDINGS:")
        print("   Pure JIT speedup: \(String(format: "%.1fx", jitSpeedup))x")
        print("   JIT+Sandbox speedup: \(String(format: "%.2fx", jitSandboxSpeedup))x")
        print("   Sandbox overhead on JIT: \(String(format: "%.1f", sandboxOverheadOfJIT))%")

        if jitSpeedup > 2.0 {
            print("\n✅ JIT compilation WORKS! This is real performance!")
        } else {
            print("\n⚠️  JIT speedup is only \(String(format: "%.1fx", jitSpeedup))x - program might be too simple")
        }
    }

    @Test("Stress Test: Massive iterations to see JIT shine")
    func stressTest() async throws {
        let massiveIterations = 2000

        print("\n=== STRESS TEST: \(massiveIterations) iterations ===")

        // JIT
        print("\nJIT mode...")
        let start1 = Date()
        for _ in 0 ..< massiveIterations {
            _ = await invokePVM(
                config: config,
                executionMode: .jit,
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([30]),
                ctx: nil
            )
        }
        let time1 = Date().timeIntervalSince(start1) * 1000

        // JIT + Sandbox
        print("JIT + Sandbox mode...")
        let start2 = Date()
        for _ in 0 ..< massiveIterations {
            _ = await invokePVM(
                config: config,
                executionMode: [.jit, .sandboxed],
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([30]),
                ctx: nil
            )
        }
        let time2 = Date().timeIntervalSince(start2) * 1000

        print("\nResults at scale:")
        print("  JIT:           \(Int(time1))ms (\(Int(time1 / Double(massiveIterations) * 1000))μs/exec)")
        print("  JIT + Sandbox: \(Int(time2))ms (\(Int(time2 / Double(massiveIterations) * 1000))μs/exec)")
        print("  Sandbox overhead: \(String(format: "%.1f", (time2 - time1) / time1 * 100))%")
    }
}
