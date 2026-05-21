import Foundation
@testable import PolkaVM
import Testing
import Utils

@Suite(.serialized)
struct SandboxPoolTests {
    @Test func queuedRequestsWaitForBusyWorker() async {
        let fibonacciProgram = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 61, 0, 0, 0, 0, 0, 51, 128, 119, 0,
            51, 8, 1, 51, 9, 1, 40, 3, 0, 149, 119, 255, 81, 7, 12, 100, 138, 200,
            152, 8, 100, 169, 40, 243, 100, 135, 51, 8, 51, 9, 61, 7, 0, 0, 2, 0,
            51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 154, 148, 170, 130, 4, 3,
        ])

        var poolConfig = SandboxPoolConfiguration.throughputOptimized
        poolConfig.poolSize = 1
        poolConfig.maxQueueDepth = 4
        poolConfig.workerWaitTimeout = 5
        poolConfig.executionTimeout = 30
        poolConfig.enableWorkerRecycling = false
        poolConfig.healthCheckInterval = 0
        poolConfig.allowOverflowWorkers = false
        poolConfig.maxOverflowWorkers = 0
        poolConfig.exhaustionPolicy = .queue

        let executor = Executor.pooled(
            mode: .sandboxed,
            config: DefaultPvmConfig(),
            poolConfig: poolConfig,
        )

        let requestCount = 3
        let successfulExecutions = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0 ..< requestCount {
                group.addTask {
                    let result = await executor.execute(
                        blob: fibonacciProgram,
                        pc: 0,
                        gas: Gas(1_000_000),
                        argumentData: Data([12]),
                        ctx: nil,
                    )
                    return result.exitReason == .halt
                }
            }

            var successCount = 0
            for await succeeded in group where succeeded {
                successCount += 1
            }
            return successCount
        }

        await executor.shutdown()

        #expect(successfulExecutions == requestCount)
    }
}
