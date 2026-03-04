import Foundation
@testable import PolkaVM
import Testing
import Utils

@Suite(.serialized)
struct TaskSleepCleanupEvidenceTests {
    @Test
    func stressSandboxFailureCleanupPath() async {
        // Keep this test inert for normal CI and local runs.
        guard ProcessInfo.processInfo.environment["RUN_TASK_SLEEP_EVIDENCE"] == "1" else {
            return
        }

        let key = "BOKA_SANDBOX_PATH"
        let originalPath = getenv(key).map { String(cString: $0) }
        defer {
            if let originalPath {
                _ = setenv(key, originalPath, 1)
            } else {
                _ = unsetenv(key)
            }
        }

        // Force spawn-success + IPC-failure path (/usr/bin/true exits immediately),
        // which executes the catch-cleanup path containing Task.sleep.
        _ = setenv(key, "/usr/bin/true", 1)

        let blob = Data([
            0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 46, 0, 0, 0, 0, 0, 38, 128, 119, 0,
            51, 8, 0, 100, 121, 40, 3, 0, 200, 137, 8, 149, 153, 255, 86, 9, 250,
            61, 8, 0, 0, 2, 0, 51, 8, 4, 51, 7, 0, 0, 2, 0, 1, 50, 0, 73, 77, 18,
            36, 24,
        ])

        let batches = Int(ProcessInfo.processInfo.environment["EVIDENCE_BATCHES"] ?? "200") ?? 200
        let parallelism = Int(ProcessInfo.processInfo.environment["EVIDENCE_PARALLEL"] ?? "256") ?? 256

        print("[TASK_SLEEP_EVIDENCE] start batches=\(batches) parallel=\(parallelism)")

        for batch in 1 ... batches {
            await withTaskGroup(of: ExitReason.self) { group in
                for _ in 0 ..< parallelism {
                    group.addTask {
                        let config = DefaultPvmConfig()
                        let (exitReason, _, _) = await invokePVM(
                            config: config,
                            executionMode: [.jit, .sandboxed],
                            blob: blob,
                            pc: 0,
                            gas: Gas(1_000_000),
                            argumentData: Data([4]),
                            ctx: nil,
                        )
                        return exitReason
                    }
                }

                var completed = 0
                for await _ in group {
                    completed += 1
                }
                #expect(completed == parallelism)
            }

            if batch % 20 == 0 || batch == 1 || batch == batches {
                print("[TASK_SLEEP_EVIDENCE] batch=\(batch)/\(batches) complete")
            }
        }

        print("[TASK_SLEEP_EVIDENCE] completed")
    }
}
