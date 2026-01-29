import Foundation
import TracingUtils
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

private let logger = Logger(label: "ChildProcessManager")

/// Process handle for managing child process lifecycle
struct ProcessHandle {
    let pid: pid_t
    let ipcFD: Int32
}

/// Manages spawning, monitoring, and reaping of child processes
actor ChildProcessManager {
    private var activeProcesses: [pid_t: ProcessHandle] = [:]
    private let defaultTimeout: TimeInterval

    init(defaultTimeout: TimeInterval = 30.0) {
        self.defaultTimeout = defaultTimeout
    }

    /// Spawn a new child process with socketpair for IPC
    ///
    /// - Parameter executablePath: Absolute or relative path to the executable to spawn.
    ///   If relative, will be searched in PATH.
    ///
    /// - Returns: Tuple of process handle and client file descriptor for IPC
    /// - Throws: IPCError if spawning fails
    func spawnChildProcess(executablePath: String) async throws -> (handle: ProcessHandle, clientFD: Int32) {
        logger.debug("Spawning child process: \(executablePath)")
        // Create socket pair for IPC
        var sockets: [Int32] = [0, 0]

        // Use the raw values directly
        #if os(Linux)
            let domain: Int32 = 1 // AF_UNIX
            let socketType: Int32 = 1 // SOCK_STREAM
        #else
            let domain: Int32 = AF_UNIX
            let socketType: Int32 = SOCK_STREAM
        #endif

        let result = Glibc.socketpair(domain, socketType, 0, &sockets)

        guard result == 0 else {
            let err = errno
            logger.error("Failed to create socketpair: \(err)")
            throw IPCError.writeFailed(Int(err))
        }

        let parentFD = sockets[0]
        let childFD = sockets[1]

        logger.debug("Created socketpair: parentFD=\(parentFD), childFD=\(childFD)")

        // Validate both FDs are valid
        let parentFlags = fcntl(parentFD, F_GETFL)
        let childFlags = fcntl(childFD, F_GETFL)
        logger.debug("Socketpair validation: parentFD flags=\(parentFlags), childFD flags=\(childFlags)")

        // Fork child process
        let pid = Glibc.fork()

        if pid < 0 {
            // Fork failed
            let err = errno
            Glibc.close(parentFD)
            Glibc.close(childFD)
            logger.error("Failed to fork: \(err)")
            throw IPCError.writeFailed(Int(err))
        } else if pid == 0 {
            // Child process - DO NOT use logging, locks, or any async-unsafe functions
            Glibc.close(parentFD)

            // Redirect stdin/stdout to /dev/null, keep stderr for debugging
            let devNull = Glibc.open("/dev/null", O_RDWR)
            if devNull >= 0 {
                Glibc.dup2(devNull, STDOUT_FILENO)
                // Glibc.dup2(devNull, STDERR_FILENO)  // Keep stderr for debugging
                Glibc.close(devNull)
            }

            // Set child FD as stdin (for IPC)
            if Glibc.dup2(childFD, STDIN_FILENO) == -1 {
                _exit(1)
            }

            Glibc.close(childFD)

            // Execute child process
            // NOTE: Using withCString here is technically not async-signal-safe
            // but it's the only way to get a C string from a Swift String
            // In practice, this usually works because we're just reading
            // existing memory, not allocating new memory
            executablePath.withCString { execPath in
                var argv: [UnsafeMutablePointer<CChar>?] = [
                    UnsafeMutablePointer(mutating: execPath),
                    nil,
                ]

                let exeResult = Glibc.execvp(execPath, &argv)

                // execvp only returns on failure
                // Use _exit() instead of exit() to avoid calling atexit() handlers
                // that were registered by the parent process
                if exeResult < 0 {
                    _exit(1)
                }
            }

            // Should never reach here
            _exit(1)
        } else {
            // Parent process
            logger.debug("Parent: Closing childFD \(childFD)")
            Glibc.close(childFD)

            // Validate parentFD is still valid after closing childFD
            let parentFlagsAfterClose = fcntl(parentFD, F_GETFL)
            logger.debug("Parent: parentFD \(parentFD) validation after close: flags=\(parentFlagsAfterClose)")

            let handle = ProcessHandle(pid: pid, ipcFD: parentFD)
            activeProcesses[pid] = handle

            logger.debug("Spawned child process: PID \(pid), returning parentFD \(parentFD)")

            // Wait a moment for child to start
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            logger.debug("Parent: Returning handle and parentFD \(parentFD) to caller")
            return (handle, parentFD)
        }
    }

    /// Wait for child process to exit
    func waitForExit(handle: ProcessHandle, timeout: TimeInterval) async throws -> Int32 {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            var status: Int32 = 0
            let result = Glibc.waitpid(handle.pid, &status, WNOHANG)

            if result < 0 {
                let err = errno
                if err == ECHILD {
                    // Child has already been reaped
                    return 0
                }
                logger.error("waitpid failed: \(err)")
                throw IPCError.readFailed(Int(err))
            }

            if result == handle.pid {
                // Child has exited
                let exitStatus = status & 0x7F // Extract exit status
                if exitStatus == 0 {
                    let exitCode = (status >> 8) & 0xFF // Extract exit code
                    logger.debug("Child process \(handle.pid) exited with code: \(exitCode)")
                    activeProcesses.removeValue(forKey: handle.pid)
                    return Int32(exitCode)
                } else {
                    let signal = exitStatus
                    logger.warning("Child process \(handle.pid) terminated by signal: \(signal)")
                    activeProcesses.removeValue(forKey: handle.pid)
                    return -1
                }
            }

            // Child still running, wait a bit
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Timeout
        logger.warning("Child process \(handle.pid) timed out, killing...")

        // Kill child process
        Glibc.kill(handle.pid, SIGTERM)

        // Wait for it to actually exit
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        var status: Int32 = 0
        _ = Glibc.waitpid(handle.pid, &status, WNOHANG)
        activeProcesses.removeValue(forKey: handle.pid)

        throw IPCError.timeout
    }

    /// Kill a child process and reap it to avoid zombies
    func kill(handle: ProcessHandle, signal: Int32 = SIGTERM) {
        logger.debug("Killing child process \(handle.pid) with signal \(signal)")
        Glibc.kill(handle.pid, signal)

        // Try to reap the process immediately to avoid zombies
        var status: Int32 = 0
        let result = Glibc.waitpid(handle.pid, &status, WNOHANG)

        if result == handle.pid {
            logger.debug("Reaped killed process \(handle.pid)")
        } else if result < 0 {
            let err = errno
            if err != ECHILD {
                logger.warning("Failed to wait for killed process \(handle.pid): \(err)")
            }
        }

        activeProcesses.removeValue(forKey: handle.pid)
    }

    /// Force reap a specific process (if it's zombie)
    func reap(handle: ProcessHandle) {
        var status: Int32 = 0
        let result = Glibc.waitpid(handle.pid, &status, WNOHANG)

        if result == handle.pid {
            logger.debug("Reaped zombie process \(handle.pid)")
            activeProcesses.removeValue(forKey: handle.pid)
        }
    }

    /// Reap zombie processes
    func reapZombies() {
        var status: Int32 = 0
        let pid = Glibc.waitpid(-1, &status, WNOHANG)

        if pid > 0 {
            logger.debug("Reaped zombie process: PID \(pid)")
            activeProcesses.removeValue(forKey: pid)
        }
    }

    /// Clean up all active processes
    func cleanup() {
        logger.debug("Cleaning up \(activeProcesses.count) active processes")

        for (_, handle) in activeProcesses {
            Glibc.close(handle.ipcFD)
            Glibc.kill(handle.pid, SIGTERM)
        }

        activeProcesses.removeAll()

        // Final reap
        var status: Int32 = 0
        while Glibc.waitpid(-1, &status, WNOHANG) > 0 {
            // Reap all zombies
        }
    }

    deinit {
        // Clean up in destructor
        // Note: This runs on arbitrary thread, be careful
        for (_, handle) in activeProcesses {
            Glibc.close(handle.ipcFD)
            Glibc.kill(handle.pid, SIGKILL)
        }
    }
}
