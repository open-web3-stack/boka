import Foundation
import TracingUtils
import Utils
import PolkaVM
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

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
            // Use _exit instead of exit for signal safety
            _exit(0)
        }

        // Handle SIGINT (Ctrl+C)
        signal(SIGINT) { _ in
            // Use _exit instead of exit for signal safety
            _exit(0)
        }

        // Handle SIGXCPU (CPU limit exceeded)
        signal(SIGXCPU) { _ in
            // Use _exit instead of exit for signal safety
            _exit(5) // Exit code for out of gas
        }
    }

    private static func handleExecuteRequest(_ request: IPCExecuteRequest) async -> IPCExecuteResponse {
        logger.debug("Received execute request: PC=\(request.pc), Gas=\(request.gas)")

        // Decode execution mode
        let mode = ExecutionMode(rawValue: request.executionMode)

        // Create ExecutorFrontendInProcess
        let executor = ExecutorFrontendInProcess(mode: mode)

        // Create config
        let config = DefaultPvmConfig()

        // Execute
        let result = await executor.execute(
            config: config,
            blob: request.blob,
            pc: request.pc,
            gas: Gas(request.gas),
            argumentData: request.argumentData,
            ctx: nil as (any InvocationContext)?  // TODO: Handle context serialization in Phase 4
        )

        logger.debug("Execution completed: \(result.exitReason), gas used: \(result.gasUsed.value)")

        return IPCExecuteResponse(
            exitReasonCode: result.exitReason.toUInt64(),
            gasUsed: result.gasUsed.value,
            outputData: result.outputData,
            errorMessage: nil
        )
    }

    // TODO: Apply security restrictions
    // private static func applySandboxSecurity() {
    //     // Apply resource limits
    //     // Apply seccomp filter
    //     // Drop capabilities
    // }
}
