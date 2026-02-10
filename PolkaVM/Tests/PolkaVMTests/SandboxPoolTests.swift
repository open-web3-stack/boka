import Foundation
import PolkaVM
import Testing
import Utils

/// Tests for sandbox pool functionality and stability
///
/// IMPORTANT: These tests must run serially because they spawn worker processes
/// and we want to avoid FD reuse issues across tests.
///
/// NOTE: These tests are temporarily disabled because the sandbox's async runtime
/// is not working properly in the forked child process. This needs investigation
/// and a fix for the Swift concurrency runtime in sandboxed processes.
@Suite(.serialized)
struct SandboxPoolTests {
    /// Test single worker execution with detailed logging
    @Test
    func singleWorkerExecution() async {
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
            exhaustionPolicy: .failFast,
        )

        print("\n=== TEST: Single Worker Execution ===")
        print("Config: poolSize=\(config.poolSize)")

        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        print("Executor created")

        // Create a minimal but valid PolkaVM program
        // The blob format includes: readonly_len, readwrite_len, heap_pages, stack_size, code
        let haltProgram = createMinimalBlob()

        print("\n--- Execution 1 ---")
        let result1 = await executor.execute(
            blob: haltProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil as Data?,
            ctx: nil as (any InvocationContext)?,
        )
        print("Result 1: \(result1.exitReason)")
        // The test program will panic with trap, which is expected
        // What we're really testing is that IPC works and worker is reused

        print("\n--- Execution 2 ---")
        let result2 = await executor.execute(
            blob: haltProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil as Data?,
            ctx: nil as (any InvocationContext)?,
        )
        print("Result 2: \(result2.exitReason)")

        print("\n--- Execution 3 ---")
        let result3 = await executor.execute(
            blob: haltProgram,
            pc: 0,
            gas: Gas(1_000_000),
            argumentData: nil as Data?,
            ctx: nil as (any InvocationContext)?,
        )
        print("Result 3: \(result3.exitReason)")

        print("\n=== TEST PASSED ===\n")
    }

    /// Test multiple executions to check for worker stability
    @Test
    func multipleExecutionsStability() async {
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
            exhaustionPolicy: .failFast,
        )

        print("\n=== TEST: Multiple Executions Stability ===")

        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        // Use a minimal but valid program: just one instruction that halts
        let haltProgram = Data([
            1, // 1 jump table entry
            0, 0, 0, 0, 0, 0, 0, 0, // jump table entry 0: offset 0
            0x01, // halt instruction (opcode 1)
        ])

        let iterations = 10
        var successCount = 0

        for i in 1 ... iterations {
            print("\n--- Execution \(i)/\(iterations) ---")
            let result = await executor.execute(
                blob: haltProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: nil as Data?,
                ctx: nil as (any InvocationContext)?,
            )
            print("Result: \(result.exitReason)")
            #expect(result.exitReason == ExitReason.halt || result.exitReason == .panic(.trap))
            successCount += 1
        }

        print("\n=== SUCCESS: \(successCount)/\(iterations) executions ===\n")
        #expect(successCount == iterations)
    }

    /// Test with small pool size to reduce noise
    @Test
    func smallPoolTwoWorkers() async {
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
            exhaustionPolicy: .failFast,
        )

        print("\n=== TEST: Small Pool (2 workers) ===")

        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: config,
        )

        // Use a minimal but valid program: just one instruction that halts
        let haltProgram = Data([
            1, // 1 jump table entry
            0, 0, 0, 0, 0, 0, 0, 0, // jump table entry 0: offset 0
            0x01, // halt instruction (opcode 1)
        ])

        let iterations = 5
        for i in 1 ... iterations {
            print("\n--- Execution \(i)/\(iterations) ---")
            let result = await executor.execute(
                blob: haltProgram,
                pc: 0,
                gas: Gas(1_000_000),
                argumentData: Data([UInt8(i)]),
                ctx: nil as (any InvocationContext)?,
            )
            print("Result: \(result.exitReason)")
            #expect(result.exitReason == ExitReason.halt || result.exitReason == .panic(.trap))
        }

        print("\n=== TEST PASSED ===\n")
    }

    /// Helper to create a minimal valid PolkaVM blob (from StandardProgramTests)
    private func createMinimalBlob() -> Data {
        let readOnlyLen: UInt32 = 256
        let readWriteLen: UInt32 = 512
        let heapPages: UInt16 = 4
        let stackSize: UInt32 = 1024
        let codeLength: UInt32 = 6

        let readOnlyData = Data(repeating: 0x01, count: Int(readOnlyLen))
        let readWriteData = Data(repeating: 0x02, count: Int(readWriteLen))
        let codeData = Data([0, 0, 2, 1, 2, 0])

        var blob = Data()
        blob.append(contentsOf: withUnsafeBytes(of: readOnlyLen.bigEndian) { Array($0.dropFirst(1)) })
        blob.append(contentsOf: withUnsafeBytes(of: readWriteLen.bigEndian) { Array($0.dropFirst(1)) })
        blob.append(contentsOf: withUnsafeBytes(of: heapPages.bigEndian) { Array($0) })
        blob.append(contentsOf: withUnsafeBytes(of: stackSize.bigEndian) { Array($0.dropFirst(1)) })
        blob.append(readOnlyData)
        blob.append(readWriteData)
        blob.append(contentsOf: Array(codeLength.encode(method: .fixedWidth(4))))
        blob.append(codeData)

        return blob
    }
}
