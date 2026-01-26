import Foundation
import PolkaVM
import Testing
import Utils

@Suite(.serialized) // Run tests in sequence
struct PerformanceComparisonTests {
    let config = DefaultPvmConfig()

    // Test program: sum integers from 0 to N
    let sumToNProgram = Data([
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
        51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
        61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
        36, 24,
    ])

    let iterations = 20

    @Test("Compare: Interpreter vs Sandbox vs Pooled")
    func compareExecutionModes() async throws {
        print("\n=== Performance Comparison: \(iterations) executions ===")

        // Test 1: Interpreter mode
        print("\n1. Interpreter mode...")
        let start1 = Date()
        for _ in 0 ..< iterations {
            _ = try await invokePVM(
                config: config,
                executionMode: [],
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([10]),
                ctx: nil
            )
        }
        let time1 = Date().timeIntervalSince(start1) * 1000
        print("   Time: \(Int(time1))ms (\(Int(time1 / Double(iterations) * 1000))μs/exec)")

        // Test 2: Sandbox mode (no pool)
        print("\n2. Sandbox mode (no pool)...")
        let start2 = Date()
        for _ in 0 ..< iterations {
            _ = try await invokePVM(
                config: config,
                executionMode: .sandboxed,
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([10]),
                ctx: nil
            )
        }
        let time2 = Date().timeIntervalSince(start2) * 1000
        print("   Time: \(Int(time2))ms (\(Int(time2 / Double(iterations) * 1000))μs/exec)")
        print("   Overhead vs interpreter: \(Int(time2 / time1 * 100))%")

        // Test 3: Sandbox mode (with pool)
        print("\n3. Sandbox mode (with pool)...")
        let pooledExecutor = Executor.pooled(
            mode: .sandboxed,
            config: config,
            poolConfig: .throughputOptimized
        )

        // Warm up the pool (spawn workers)
        print("   Warming up pool...")
        _ = try await pooledExecutor.execute(
            blob: sumToNProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([10]),
            ctx: nil
        )

        print("   Running benchmark...")
        let start3 = Date()
        for _ in 0 ..< iterations {
            _ = try await pooledExecutor.execute(
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([10]),
                ctx: nil
            )
        }
        let time3 = Date().timeIntervalSince(start3) * 1000
        print("   Time: \(Int(time3))ms (\(Int(time3 / Double(iterations) * 1000))μs/exec)")
        print("   Overhead vs interpreter: \(Int(time3 / time1 * 100))%")
        print("   Speedup vs non-pooled: \(Int(time2 / time3 * 100))%")

        print("\n=== Summary ===")
        print("Interpreter:        \(Int(time1))ms")
        print("Sandbox:           \(Int(time2))ms (\(Int(time2 / time1 * 100))% overhead)")
        print("Pooled Sandbox:     \(Int(time3))ms (\(Int(time3 / time1 * 100))% overhead)")
        if time3 > 0, time2 > 0 {
            print("Pool improvement:  \(max(0, Int((time2 - time3) / time2 * 100)))% faster")
        }
    }
}
