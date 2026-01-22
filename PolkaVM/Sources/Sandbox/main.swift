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

        // Apply security restrictions
        applySandboxSecurity()

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

    /// Apply security restrictions to sandbox the process
    /// This is a basic implementation. For production use, consider:
    /// - Linux namespaces (mount, PID, network)
    /// - seccomp-bpf for system call filtering
    /// - Landlock for filesystem restrictions
    /// - chroot for filesystem isolation
    private static func applySandboxSecurity() {
        #if os(Linux)
        // 1. Set resource limits to prevent resource exhaustion
        setResourceLimits()

        // 2. Drop privileges if running as root (not applicable in most cases)
        // dropPrivileges()

        // Note: For production use, consider:
        // - seccomp filter to restrict syscalls
        // - unshare() for Linux namespaces
        // - chroot() for filesystem isolation
        // - Landlock for fine-grained filesystem access control

        logger.info("Basic sandbox security applied")
        #else
        logger.warning("Sandbox security restrictions not implemented for this platform")
        #endif
    }

    #if os(Linux)
    /// Set resource limits to constrain the sandboxed process
    private static func setResourceLimits() {
        var limit = rlimit()

        // Limit CPU time (5 seconds)
        limit.rlim_cur = 5
        limit.rlim_max = 10
        if setrlimit(Int32(RLIMIT_CPU.rawValue), &limit) != 0 {
            logger.warning("Failed to set CPU time limit: \(String(cString: strerror(errno)))")
        }

        // Limit address space to 4GB (matches PVM memory size)
        limit.rlim_cur = UInt(4) * 1024 * 1024 * 1024
        limit.rlim_max = UInt(4) * 1024 * 1024 * 1024
        if setrlimit(Int32(RLIMIT_AS.rawValue), &limit) != 0 {
            logger.warning("Failed to set address space limit: \(String(cString: strerror(errno)))")
        }

        // Limit number of file descriptors
        limit.rlim_cur = 32
        limit.rlim_max = 64
        if setrlimit(Int32(RLIMIT_NOFILE.rawValue), &limit) != 0 {
            logger.warning("Failed to set file descriptor limit: \(String(cString: strerror(errno)))")
        }

        // Note: RLIMIT_NPROC may not be available on all systems
        // Skip for portability
    }
    #endif

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
}
