import Foundation
import TracingUtils
import PolkaVM

private let logger = Logger(label: "Boka-Sandbox")

@main
struct SandboxMain {
    static func main() async {
        logger.info("Boka VM Sandbox starting...")

        // Set up signal handlers for clean shutdown
        setupSignalHandlers()

        // TODO: Apply security restrictions
        // applySandboxSecurity()

        // Create and run IPC server
        let server = IPCServer()
        server.setFileDescriptor(STDIN_FILENO)

        logger.info("Sandbox process ready, listening for IPC messages")

        await server.run { request in
            // Handle execute request
            await handleExecuteRequest(request)
        }

        logger.info("Sandbox process exiting")
    }

    private static func setupSignalHandlers() {
        // Handle SIGTERM for graceful shutdown
        signal(SIGTERM) { _ in
            logger.info("Received SIGTERM, shutting down...")
            exit(0)
        }

        // Handle SIGINT (Ctrl+C)
        signal(SIGINT) { _ in
            logger.info("Received SIGINT, shutting down...")
            exit(0)
        }

        // Handle SIGXCPU (CPU limit exceeded)
        signal(SIGXCPU) { _ in
            logger.error("CPU time limit exceeded")
            exit(5) // Exit code for out of gas
        }
    }

    private static func handleExecuteRequest(_ request: IPCExecuteRequest) async -> IPCExecuteResponse {
        do {
            logger.debug("Received execute request: PC=\(request.pc), Gas=\(request.gas)")

            // Decode execution mode
            let mode = ExecutionMode(rawValue: request.executionMode)

            // Create ExecutorFrontendInProcess
            let executor = ExecutorFrontendInProcess(mode: mode)

            // Create config
            let config = PvmConfig(memorySize: 16 * 1024 * 1024) // 16 MB default

            // Execute
            let exitReason = await executor.execute(
                config: config,
                blob: request.blob,
                pc: request.pc,
                gas: Gas(request.gas),
                argumentData: request.argumentData,
                ctx: nil  // TODO: Handle context serialization in Phase 4
            )

            logger.debug("Execution completed: \(exitReason)")

            return IPCExecuteResponse(
                exitReasonCode: exitReason.toUInt64(),
                gasUsed: request.gas,  // TODO: Track actual gas used
                outputData: nil,  // TODO: Read output from state
                errorMessage: nil
            )

        } catch {
            logger.error("Execution failed: \(error)")

            return IPCExecuteResponse(
                exitReasonCode: ExitReason.panic(.trap).toUInt64(),
                gasUsed: 0,
                outputData: nil,
                errorMessage: "\(error)"
            )
        }
    }

    // TODO: Apply security restrictions
    // private static func applySandboxSecurity() {
    //     // Apply resource limits
    //     // Apply seccomp filter
    //     // Drop capabilities
    // }
}
