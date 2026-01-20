import Foundation
import TracingUtils
import Utils

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
    ) async -> ExitReason {
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

        do {
            // Spawn child process
            let (handle, clientFD) = try await childProcessManager.spawnChildProcess(
                executablePath: executablePath
            )

            // Create IPC client
            let ipcClient = IPCClient()
            ipcClient.setFileDescriptor(clientFD)

            // Send execute request
            let result = try await ipcClient.sendExecuteRequest(
                blob: blob,
                pc: pc,
                gas: gas.value,
                argumentData: argumentData,
                executionMode: mode
            )

            // Clean up
            ipcClient.close()

            // Wait for child to exit
            let _ = try? await childProcessManager.waitForExit(
                handle: handle,
                timeout: 30.0
            )

            return result.exitReason

        } catch {
            logger.error("Sandboxed execution failed: \(error)")

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
