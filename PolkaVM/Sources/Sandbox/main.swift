import Foundation
import PolkaVM
import TracingUtils
import Utils
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif
#if os(macOS)
    import MacOSSandboxSupport
#endif

private let logger = Logger(label: "Boka-Sandbox")
private let sandboxDebugEnabled: Bool = {
    guard let value = ProcessInfo.processInfo.environment["BOKA_SANDBOX_DEBUG"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased(),
        !value.isEmpty
    else {
        return false
    }

    return value == "1" || value == "true" || value == "yes" || value == "on"
}()

/// Helper function to write debug messages to stderr
private func debugWrite(_ message: String) {
    guard sandboxDebugEnabled else {
        return
    }

    _ = message.withCString { ptr in
        #if canImport(Glibc)
            Glibc.write(STDERR_FILENO, ptr, message.count)
        #elseif canImport(Darwin)
            Darwin.write(STDERR_FILENO, ptr, message.count)
        #endif
    }
}

@main
enum SandboxMain {
    static func main() async {
        logger.debug("Boka VM Sandbox starting...")

        // DEBUG: Track initialization
        debugWrite("Sandbox: main() started\n")

        // Set up signal handlers for clean shutdown
        setupSignalHandlers()
        debugWrite("Sandbox: Signal handlers set\n")

        // Apply security restrictions
        applySandboxSecurity()
        debugWrite("Sandbox: Security applied\n")

        // Create and run IPC server
        let server = IPCServer()
        debugWrite("Sandbox: IPCServer created\n")

        server.setFileDescriptor(STDIN_FILENO)
        debugWrite("Sandbox: FD set\n")

        logger.debug("Sandbox process ready, listening for IPC messages")

        await server.run { request in
            // Handle execute request
            await handleExecuteRequest(request)
        }

        logger.debug("Sandbox process exiting")
    }

    private static func setupSignalHandlers() {
        debugWrite("Sandbox: Setting up signal handlers\n")

        // Handle SIGTERM for graceful shutdown
        signal(SIGTERM) { _ in
            debugWrite("Sandbox: Received SIGTERM, exiting\n")
            // Use _exit instead of exit for signal safety
            _exit(0)
        }

        // Handle SIGINT (Ctrl+C)
        signal(SIGINT) { _ in
            debugWrite("Sandbox: Received SIGINT, exiting\n")
            // Use _exit instead of exit for signal safety
            _exit(0)
        }

        // Handle SIGXCPU (CPU limit exceeded)
        signal(SIGXCPU) { _ in
            debugWrite("Sandbox: Received SIGXCPU, exiting\n")
            // Use _exit instead of exit for signal safety
            _exit(5) // Exit code for out of gas
        }

        debugWrite("Sandbox: Signal handlers set up complete\n")
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
            // TEMPORARILY DISABLED for debugging
            // setResourceLimits()

            // 2. Drop privileges if running as root (not applicable in most cases)
            // dropPrivileges()

            // Note: For production use, consider:
            // - seccomp filter to restrict syscalls
            // - unshare() for Linux namespaces
            // - chroot() for filesystem isolation
            // - Landlock for fine-grained filesystem access control

            logger.debug("Basic sandbox security applied")
        #elseif os(macOS)
            // Constrain CPU/file descriptor usage before entering Seatbelt.
            setResourceLimits()

            guard applyMacOSSandboxProfile() else {
                debugWrite("Sandbox: Failed to apply macOS sandbox profile\n")
                logger.error("Failed to apply macOS sandbox profile")
                _exit(1)
            }

            logger.debug("macOS sandbox security applied")
        #else
            logger.warning("Sandbox security restrictions not implemented for this platform")
        #endif
    }

    #if os(Linux) || os(macOS)
        /// Set resource limits to constrain the sandboxed process
        private static func setResourceLimits() {
            #if os(Linux)
                let cpuResource = Int32(RLIMIT_CPU.rawValue)
                let memoryResource: Int32? = Int32(RLIMIT_AS.rawValue)
                let fileResource = Int32(RLIMIT_NOFILE.rawValue)
            #else
                let cpuResource = RLIMIT_CPU
                // Darwin commonly rejects finite memory rlimits (EINVAL), so we skip memory limit here.
                let memoryResource: Int32? = nil
                let fileResource = RLIMIT_NOFILE
            #endif

            // Limit CPU time (5 seconds)
            setLimit(
                resource: cpuResource,
                soft: rlim_t(5),
                hard: rlim_t(10),
                name: "CPU time",
            )

            // Limit memory usage to 4GB (matches PVM memory size)
            if let memoryResource {
                let memoryLimit = rlim_t(4) * 1024 * 1024 * 1024
                setLimit(
                    resource: memoryResource,
                    soft: memoryLimit,
                    hard: memoryLimit,
                    name: "memory",
                )
            }

            // Limit number of file descriptors
            setLimit(
                resource: fileResource,
                soft: rlim_t(32),
                hard: rlim_t(64),
                name: "file descriptor",
            )

            // Note: RLIMIT_NPROC may not be available on all systems
            // Skip for portability
        }

        private static func setLimit(resource: Int32, soft: rlim_t, hard: rlim_t, name: String) {
            var current = rlimit()
            if getrlimit(resource, &current) != 0 {
                logger.warning("Failed to read \(name) hard limit: \(String(cString: strerror(errno)))")
                return
            }

            let effectiveHard = min(hard, current.rlim_max)
            let effectiveSoft = min(soft, effectiveHard)

            var requested = rlimit(rlim_cur: effectiveSoft, rlim_max: effectiveHard)
            if setrlimit(resource, &requested) != 0 {
                logger.warning("Failed to set \(name) limit: \(String(cString: strerror(errno)))")
            }
        }
    #endif

    #if os(macOS)
        private static func applyMacOSSandboxProfile() -> Bool {
            var errorBuffer: UnsafeMutablePointer<CChar>?
            let result = boka_apply_macos_sandbox(&errorBuffer)

            guard result == 0 else {
                if let errorBuffer {
                    let message = String(cString: errorBuffer)
                    logger.error("macOS sandbox initialization failed: \(message)")
                    boka_free_macos_sandbox_error(errorBuffer)
                } else {
                    logger.error("macOS sandbox initialization failed with errno: \(errno)")
                }
                return false
            }

            if let errorBuffer {
                boka_free_macos_sandbox_error(errorBuffer)
            }

            return true
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
            ctx: nil as (any InvocationContext)?, // TODO: Handle context serialization in Phase 4
        )

        logger.debug("Execution completed: \(result.exitReason), gas used: \(result.gasUsed.value)")

        return IPCExecuteResponse(
            exitReasonCode: result.exitReason.toUInt64(),
            gasUsed: result.gasUsed.value,
            outputData: result.outputData,
            errorMessage: nil,
        )
    }
}
