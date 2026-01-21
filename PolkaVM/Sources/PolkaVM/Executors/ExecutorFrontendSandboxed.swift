import Foundation
import TracingUtils
import Utils
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class ExecutorFrontendSandboxed: ExecutorFrontend {
    private let logger = Logger(label: "ExecutorFrontendSandboxed")
    private let mode: ExecutionMode
    private let childProcessManager: ChildProcessManager
    private let executablePath: String

    init(mode: ExecutionMode) {
        self.mode = mode
        self.executablePath = "boka-sandbox"
        self.childProcessManager = ChildProcessManager()
    }

    func execute(
        config: PvmConfig,
        blob: Data,
        pc: UInt32,
        gas: Gas,
        argumentData: Data?,
        ctx: (any InvocationContext)?
    ) async -> VMExecutionResult {
        // TODO: For now, we still need to handle context properly
        // The context serialization will be implemented in Phase 4
        if ctx != nil {
            logger.warning("Sandboxed mode does not support InvocationContext yet, falling back to in-process")
            let inProcess = ExecutorFrontendInProcess(mode: mode)
            return await inProcess.execute(
                config: config,
                blob: blob,
                pc: pc,
                gas: gas,
                argumentData: argumentData,
                ctx: ctx
            )
        }

        // Declare handle outside do block so it's accessible in catch for cleanup
        var handle: ProcessHandle?
        var clientFD: Int32?

        do {
            // Spawn child process
            (handle, clientFD) = try await childProcessManager.spawnChildProcess(
                executablePath: executablePath
            )

            // Create IPC client
            let ipcClient = IPCClient()
            ipcClient.setFileDescriptor(clientFD!)

            // Send execute request
            let result = try await ipcClient.sendExecuteRequest(
                blob: blob,
                pc: pc,
                gas: gas.value,
                argumentData: argumentData,
                executionMode: mode
            )

            // Clean up IPC
            ipcClient.close()

            // Wait for child to exit
            if let handle = handle {
                let _ = try? await childProcessManager.waitForExit(
                    handle: handle,
                    timeout: 30.0
                )
            }

            return VMExecutionResult(
                exitReason: result.exitReason,
                gasUsed: Gas(result.gasUsed),
                outputData: result.outputData
            )

        } catch {
            logger.error("Sandboxed execution failed: \(error)")

            // Clean up child process if it was spawned
            if let handle = handle {
                // Try to kill the process and reap it to avoid zombies
                await childProcessManager.kill(handle: handle)
                // Try one more reap after a short delay
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                await childProcessManager.reap(handle: handle)
            }

            // Close client FD if it was opened
            if let fd = clientFD, fd >= 0 {
                close(fd)
            }

            // Fallback to in-process on error
            logger.warning("Falling back to in-process execution")
            let inProcess = ExecutorFrontendInProcess(mode: mode)
            return await inProcess.execute(
                config: config,
                blob: blob,
                pc: pc,
                gas: gas,
                argumentData: argumentData,
                ctx: ctx
            )
        }
    }
}
