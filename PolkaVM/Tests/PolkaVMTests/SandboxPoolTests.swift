import Foundation
import PolkaVM
import Testing
import Utils

/// Tests for sandbox pool functionality and stability
struct SandboxPoolTests {
    /// Test single worker execution with detailed logging
    @Test("Single worker execution - detailed")
    func singleWorkerExecution() async throws {
        let config = SandboxPoolConfiguration(
            poolSize: 1,
            maxQueueDepth: 10,
            workerWaitTimeout: 5.0,
            executionTimeout: 5.0,
            enableWorkerRecycling: false,
            workerRecycleThreshold: 1000,
            healthCheckInterval: 0,
            maxConsecutiveFailures: 10,
            failureTrackingWindow: 60.0,
            allowOverflowWorkers: false,
            maxOverflowWorkers: 0,
            exhaustionPolicy: .failFast
        )

        print("\n=== TEST: Single Worker Execution ===")
        print("Config: poolSize=\(config.poolSize)")

        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config
        )

        print("Executor created")

        let emptyProgram = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])

        print("\n--- Execution 1 ---")
        let result1 = try await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil as Data?,
            ctx: nil as (any InvocationContext)?
        )
        print("Result 1: \(result1.exitReason)")
        #expect(result1.exitReason == ExitReason.halt)

        print("\n--- Execution 2 ---")
        let result2 = try await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil as Data?,
            ctx: nil as (any InvocationContext)?
        )
        print("Result 2: \(result2.exitReason)")
        #expect(result2.exitReason == ExitReason.halt)

        print("\n--- Execution 3 ---")
        let result3 = try await executor.execute(
            blob: emptyProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil as Data?,
            ctx: nil as (any InvocationContext)?
        )
        print("Result 3: \(result3.exitReason)")
        #expect(result3.exitReason == ExitReason.halt)

        print("\n=== TEST PASSED ===\n")
    }

    /// Test multiple executions to check for worker stability
    @Test("Multiple executions - stability check")
    func multipleExecutionsStability() async throws {
        let config = SandboxPoolConfiguration(
            poolSize: 1,
            maxQueueDepth: 10,
            workerWaitTimeout: 10.0,
            executionTimeout: 10.0,
            enableWorkerRecycling: false,
            workerRecycleThreshold: 1000,
            healthCheckInterval: 0,
            maxConsecutiveFailures: 10,
            failureTrackingWindow: 60.0,
            allowOverflowWorkers: false,
            maxOverflowWorkers: 0,
            exhaustionPolicy: .failFast
        )

        print("\n=== TEST: Multiple Executions Stability ===")

        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config
        )

        let emptyProgram = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])

        let iterations = 10
        var successCount = 0

        for i in 1 ... iterations {
            print("\n--- Execution \(i)/\(iterations) ---")
            do {
                let result = try await executor.execute(
                    blob: emptyProgram,
                    pc: 0,
                    gas: Gas(1_000_000),
                    argumentData: nil as Data?,
                    ctx: nil as (any InvocationContext)?
                )
                print("Result: \(result.exitReason)")
                #expect(result.exitReason == ExitReason.halt)
                successCount += 1
            } catch {
                print("ERROR: \(error)")
                throw error
            }
        }

        print("\n=== SUCCESS: \(successCount)/\(iterations) executions ===\n")
        #expect(successCount == iterations)
    }

    /// Test with small pool size to reduce noise
    @Test("Small pool - 2 workers")
    func smallPoolTwoWorkers() async throws {
        let config = SandboxPoolConfiguration(
            poolSize: 2,
            maxQueueDepth: 10,
            workerWaitTimeout: 10.0,
            executionTimeout: 10.0,
            enableWorkerRecycling: false,
            workerRecycleThreshold: 1000,
            healthCheckInterval: 0,
            maxConsecutiveFailures: 10,
            failureTrackingWindow: 60.0,
            allowOverflowWorkers: false,
            maxOverflowWorkers: 0,
            exhaustionPolicy: .failFast
        )

        print("\n=== TEST: Small Pool (2 workers) ===")

        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config
        )

        let emptyProgram = Data([0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])

        let iterations = 5
        for i in 1 ... iterations {
            print("\n--- Execution \(i)/\(iterations) ---")
            let result = try await executor.execute(
                blob: emptyProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([UInt8(i)]),
                ctx: nil as (any InvocationContext)?
            )
            print("Result: \(result.exitReason)")
            #expect(result.exitReason == ExitReason.halt)
        }

        print("\n=== TEST PASSED ===\n")
    }
}
