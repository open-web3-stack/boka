import Foundation
import PolkaVM
import Testing
import Utils

@Suite(.serialized) // Run tests in sequence
struct ComprehensivePerformanceTests {
    let config = DefaultPvmConfig()

    // MARK: - Test Programs

    // 1. Simple halt program - minimal overhead
    let haltProgram = Data([
        1, // 1 jump table entry
        0, 0, 0, 0, 0, 0, 0, 0, // jump table entry 0: offset 0
        0x01, // halt instruction (opcode 1)
    ])

    // 2. Sum integers 0 to N - simple loop
    let sumToNProgram = Data([
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
        51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
        61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
        36, 24,
    ])

    // 3. Fibonacci - recursive with branching
    let fibonacciProgram = Data([
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
        51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
        152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
        51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
    ])

    // 4. Memory intensive - allocate and write to memory
    let memoryIntensiveProgram = Data([
        // Complex program with multiple memory operations
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 51, 128, 119, 0, // load imm
        51, 8, 0, // load imm 0
        121, 40, 3, 0, // loop start
        200, 137, 8, 149, 153, 255, 86, 9, 250, // memory operations
        61, 8, 0, 0, 2, 0, // increment
        51, 8, 100, // load imm 100
        40, 3, 0, 149, 153, 255, // branch
        51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18, 36, 24, // exit
    ])

    // MARK: - Test Configuration

    let smallIterations = 50
    let mediumIterations = 200
    let largeIterations = 1000

    // MARK: - Performance Tests

    @Test("Performance: Small program (halt) - 50 iterations")
    func performanceSmallProgram() async throws {
        await runPerformanceTest(
            name: "Halt Program",
            blob: haltProgram,
            argumentData: Data(),
            iterations: smallIterations,
            expectedComplexity: "minimal"
        )
    }

    @Test("Performance: Medium program (sum to N) - 200 iterations")
    func performanceMediumProgram() async throws {
        await runPerformanceTest(
            name: "Sum to N Program",
            blob: sumToNProgram,
            argumentData: Data([20]),
            iterations: mediumIterations,
            expectedComplexity: "simple loop"
        )
    }

    @Test("Performance: Complex program (fibonacci) - 200 iterations")
    func performanceComplexProgram() async throws {
        await runPerformanceTest(
            name: "Fibonacci Program",
            blob: fibonacciProgram,
            argumentData: Data([12]),
            iterations: mediumIterations,
            expectedComplexity: "recursive with branching"
        )
    }

    @Test("Performance: Memory intensive - 200 iterations")
    func performanceMemoryIntensive() async throws {
        await runPerformanceTest(
            name: "Memory Intensive Program",
            blob: memoryIntensiveProgram,
            argumentData: Data(),
            iterations: mediumIterations,
            expectedComplexity: "multiple memory ops"
        )
    }

    @Test("Performance: Large scale (sum to N) - 1000 iterations")
    func performanceLargeScale() async throws {
        await runPerformanceTest(
            name: "Large Scale Sum to N",
            blob: sumToNProgram,
            argumentData: Data([50]),
            iterations: largeIterations,
            expectedComplexity: "simple loop, many iterations"
        )
    }

    @Test("Performance: Pool efficiency - Compare pool vs no-pool at scale")
    func performancePoolEfficiency() async throws {
        print("\n=== Pool Efficiency Test: \(largeIterations) iterations ===")

        // Test 1: Sandbox without pool
        print("\n1. Sandbox (no pool)...")
        let start1 = Date()
        for _ in 0 ..< largeIterations {
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
        let time1 = Date().timeIntervalSince(start1) * 1000
        print("   Time: \(Int(time1))ms (\(Int(time1 / Double(largeIterations) * 1000))μs/exec)")

        // Test 2: Sandbox with pool (warm)
        print("\n2. Sandbox (with warm pool)...")
        let pooledExecutor = Executor.pooled(
            mode: [.jit, .sandboxed],
            config: config,
            poolConfig: .throughputOptimized
        )

        // Warm up the pool
        print("   Warming up pool...")
        _ = await pooledExecutor.execute(
            blob: sumToNProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([30]),
            ctx: nil
        )

        print("   Running benchmark...")
        let start2 = Date()
        for _ in 0 ..< largeIterations {
            _ = await pooledExecutor.execute(
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([30]),
                ctx: nil
            )
        }
        let time2 = Date().timeIntervalSince(start2) * 1000
        print("   Time: \(Int(time2))ms (\(Int(time2 / Double(largeIterations) * 1000))μs/exec)")

        // Calculate improvements
        let overhead = Int((time2 - time1) / time1 * 100)
        let speedup = Int((time1 - time2) / time1 * 100)

        print("\n=== Results ===")
        print("No pool:    \(Int(time1))ms")
        print("With pool:  \(Int(time2))ms")

        if time2 < time1 {
            print("Pool speedup:  \(speedup)% faster")
        } else {
            print("Pool overhead: \(overhead)% slower")
        }

        print("\nPer-execution overhead:")
        let noPoolPerExec = time1 / Double(largeIterations)
        let poolPerExec = time2 / Double(largeIterations)
        print("  No pool: \(Int(noPoolPerExec * 1000))μs")
        print("  With pool: \(Int(poolPerExec * 1000))μs")
        print("  Difference: \(Int(abs(poolPerExec - noPoolPerExec) * 1000))μs")
    }

    @Test("Performance: Interpreter baseline - Compare all modes at scale")
    func performanceAllModes() async throws {
        print("\n=== All Modes Comparison: \(mediumIterations) iterations ===")

        // Test 1: Interpreter
        print("\n1. Interpreter mode...")
        let start1 = Date()
        for _ in 0 ..< mediumIterations {
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
        print("   Time: \(Int(time1))ms (\(Int(time1 / Double(mediumIterations) * 1000))μs/exec)")

        // Test 2: Sandbox (no pool)
        print("\n2. Sandbox mode (no pool)...")
        let start2 = Date()
        for _ in 0 ..< mediumIterations {
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
        let time2 = Date().timeIntervalSince(start2) * 1000
        print("   Time: \(Int(time2))ms (\(Int(time2 / Double(mediumIterations) * 1000))μs/exec)")

        // Test 3: Sandbox (with pool)
        print("\n3. Sandbox mode (with pool)...")
        let pooledExecutor = Executor.pooled(
            mode: [.jit, .sandboxed],
            config: config,
            poolConfig: .throughputOptimized
        )

        // Warm up
        _ = await pooledExecutor.execute(
            blob: sumToNProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: Data([25]),
            ctx: nil
        )

        let start3 = Date()
        for _ in 0 ..< mediumIterations {
            _ = await pooledExecutor.execute(
                blob: sumToNProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([25]),
                ctx: nil
            )
        }
        let time3 = Date().timeIntervalSince(start3) * 1000
        print("   Time: \(Int(time3))ms (\(Int(time3 / Double(mediumIterations) * 1000))μs/exec)")

        // Summary
        print("\n=== Summary ===")
        print("Interpreter:     \(Int(time1))ms (baseline)")
        print("Sandbox:         \(Int(time2))ms (\(Int(time2 / time1 * 100))% of baseline)")
        print("Pooled Sandbox:  \(Int(time3))ms (\(Int(time3 / time1 * 100))% of baseline)")

        let sandboxOverhead = Int((time2 - time1) / time1 * 100)
        let poolOverhead = Int((time3 - time1) / time1 * 100)

        print("\nOverhead vs Interpreter:")
        print("  Sandbox:         \(sandboxOverhead)%")
        print("  Pooled Sandbox:  \(poolOverhead)%")

        if time3 < time2 {
            let poolImprovement = Int((time2 - time3) / time2 * 100)
            print("\nPool improvement: \(poolImprovement)% faster than non-pooled sandbox")
        }
    }

    // MARK: - Helper Methods

    private func runPerformanceTest(
        name: String,
        blob: Data,
        argumentData: Data,
        iterations: Int,
        expectedComplexity: String
    ) async {
        print("\n=== \(name) ===")
        print("Complexity: \(expectedComplexity)")
        print("Iterations: \(iterations)")

        // Test JIT mode (baseline)
        print("JIT mode...")
        let start1 = Date()
        for _ in 0 ..< iterations {
            _ = await invokePVM(
                config: config,
                executionMode: .jit,
                blob: blob,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: argumentData,
                ctx: nil
            )
        }
        let time1 = Date().timeIntervalSince(start1) * 1000
        let perExec1 = time1 / Double(iterations)
        print("  \(Int(time1))ms (\(Int(perExec1 * 1000))μs/exec)")

        // Test JIT + Sandbox mode
        print("JIT + Sandbox mode...")
        let start2 = Date()
        for _ in 0 ..< iterations {
            _ = await invokePVM(
                config: config,
                executionMode: [.jit, .sandboxed],
                blob: blob,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: argumentData,
                ctx: nil
            )
        }
        let time2 = Date().timeIntervalSince(start2) * 1000
        let perExec2 = time2 / Double(iterations)
        print("  \(Int(time2))ms (\(Int(perExec2 * 1000))μs/exec)")

        // Test pooled JIT + Sandbox mode
        print("Pooled JIT + Sandbox mode...")
        let pooledExecutor = Executor.pooled(
            mode: [.jit, .sandboxed],
            config: config,
            poolConfig: .throughputOptimized
        )

        // Warm up
        _ = await pooledExecutor.execute(
            blob: blob,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: argumentData,
            ctx: nil
        )

        let start3 = Date()
        for _ in 0 ..< iterations {
            _ = await pooledExecutor.execute(
                blob: blob,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: argumentData,
                ctx: nil
            )
        }
        let time3 = Date().timeIntervalSince(start3) * 1000
        let perExec3 = time3 / Double(iterations)
        print("  \(Int(time3))ms (\(Int(perExec3 * 1000))μs/exec)")
    }
}
