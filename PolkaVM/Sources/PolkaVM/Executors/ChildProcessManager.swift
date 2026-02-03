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
        #if os(Linux)
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

            #if canImport(Glibc)
                let result = Glibc.socketpair(domain, socketType, 0, &sockets)
            #elseif canImport(Darwin)
                let result = Darwin.socketpair(domain, socketType, 0, &sockets)
            #endif

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

            // Convert executable path to null-terminated C string array BEFORE fork
            // This is async-signal-safe and avoids unsafe withCString in child after fork
            let execPathCArray = executablePath.utf8CString

            // Fork child process
            #if canImport(Glibc)
                let pid = Glibc.fork()
            #elseif canImport(Darwin)
                let pid = Darwin.fork()
            #endif

            if pid < 0 {
                // Fork failed
                let err = errno
                #if canImport(Glibc)
                    Glibc.close(parentFD)
                    Glibc.close(childFD)
                #elseif canImport(Darwin)
                    Darwin.close(parentFD)
                    Darwin.close(childFD)
                #endif
                logger.error("Failed to fork: \(err)")
                throw IPCError.writeFailed(Int(err))
            } else if pid == 0 {
                // Child process - DO NOT use logging, locks, or any async-unsafe functions
                #if canImport(Glibc)
                    Glibc.close(parentFD)
                #elseif canImport(Darwin)
                    Darwin.close(parentFD)
                #endif

                // Redirect stdin/stdout to /dev/null, keep stderr for debugging
                #if canImport(Glibc)
                    let devNull = Glibc.open("/dev/null", O_RDWR)
                #elseif canImport(Darwin)
                    let devNull = Darwin.open("/dev/null", O_RDWR)
                #endif
                if devNull >= 0 {
                    #if canImport(Glibc)
                        Glibc.dup2(devNull, STDOUT_FILENO)
                        // Glibc.dup2(devNull, STDERR_FILENO)  // Keep stderr for debugging
                        Glibc.close(devNull)
                    #elseif canImport(Darwin)
                        Darwin.dup2(devNull, STDOUT_FILENO)
                        // Darwin.dup2(devNull, STDERR_FILENO)  // Keep stderr for debugging
                        Darwin.close(devNull)
                    #endif
                }

                // Set child FD as stdin (for IPC)
                #if canImport(Glibc)
                    if Glibc.dup2(childFD, STDIN_FILENO) == -1 {
                        _exit(1)
                    }
                #elseif canImport(Darwin)
                    if Darwin.dup2(childFD, STDIN_FILENO) == -1 {
                        _exit(1)
                    }
                #endif

                #if canImport(Glibc)
                    Glibc.close(childFD)
                #elseif canImport(Darwin)
                    Darwin.close(childFD)
                #endif

                // Execute child process
                // Use pre-allocated C string array (async-signal-safe)
                // withUnsafeBufferPointer is safe here because we're in the child process
                // and the array lives until execvp replaces the process image
                execPathCArray.withUnsafeBufferPointer { buffer in
                    let execPath = buffer.baseAddress!
                    var argv: [UnsafeMutablePointer<CChar>?] = [
                        UnsafeMutablePointer(mutating: execPath),
                        nil,
                    ]

                    #if canImport(Glibc)
                        let exeResult = Glibc.execvp(execPath, &argv)
                    #elseif canImport(Darwin)
                        let exeResult = Darwin.execvp(execPath, &argv)
                    #endif

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
                #if canImport(Glibc)
                    Glibc.close(childFD)
                #elseif canImport(Darwin)
                    Darwin.close(childFD)
                #endif

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
        #else
            throw IPCError.childProcessError("Sandboxed execution is not supported on this platform")
        #endif
    }

    /// Wait for child process to exit
    func waitForExit(handle: ProcessHandle, timeout: TimeInterval) async throws -> Int32 {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            var status: Int32 = 0
            #if canImport(Glibc)
                let result = Glibc.waitpid(handle.pid, &status, WNOHANG)
            #elseif canImport(Darwin)
                let result = Darwin.waitpid(handle.pid, &status, WNOHANG)
            #endif

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
        #if canImport(Glibc)
            Glibc.kill(handle.pid, SIGTERM)
        #elseif canImport(Darwin)
            Darwin.kill(handle.pid, SIGTERM)
        #endif

        // Wait for it to actually exit
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        var status: Int32 = 0
        #if canImport(Glibc)
            _ = Glibc.waitpid(handle.pid, &status, WNOHANG)
        #elseif canImport(Darwin)
            _ = Darwin.waitpid(handle.pid, &status, WNOHANG)
        #endif
        activeProcesses.removeValue(forKey: handle.pid)

        throw IPCError.timeout
    }

    /// Kill a child process and reap it to avoid zombies
    func kill(handle: ProcessHandle, signal: Int32 = SIGTERM) {
        logger.debug("Killing child process \(handle.pid) with signal \(signal)")
        #if canImport(Glibc)
            Glibc.kill(handle.pid, signal)
        #elseif canImport(Darwin)
            Darwin.kill(handle.pid, signal)
        #endif

        // Try to reap the process immediately to avoid zombies
        var status: Int32 = 0
        #if canImport(Glibc)
            let result = Glibc.waitpid(handle.pid, &status, WNOHANG)
        #elseif canImport(Darwin)
            let result = Darwin.waitpid(handle.pid, &status, WNOHANG)
        #endif

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
        #if canImport(Glibc)
            let result = Glibc.waitpid(handle.pid, &status, WNOHANG)
        #elseif canImport(Darwin)
            let result = Darwin.waitpid(handle.pid, &status, WNOHANG)
        #endif

        if result == handle.pid {
            logger.debug("Reaped zombie process \(handle.pid)")
            activeProcesses.removeValue(forKey: handle.pid)
        }
    }

    /// Reap zombie processes
    func reapZombies() {
        var status: Int32 = 0
        #if canImport(Glibc)
            let pid = Glibc.waitpid(-1, &status, WNOHANG)
        #elseif canImport(Darwin)
            let pid = Darwin.waitpid(-1, &status, WNOHANG)
        #endif

        if pid > 0 {
            logger.debug("Reaped zombie process: PID \(pid)")
            activeProcesses.removeValue(forKey: pid)
        }
    }

    /// Clean up all active processes
    func cleanup() {
        logger.debug("Cleaning up \(activeProcesses.count) active processes")

        for (_, handle) in activeProcesses {
            #if canImport(Glibc)
                Glibc.close(handle.ipcFD)
                Glibc.kill(handle.pid, SIGTERM)
            #elseif canImport(Darwin)
                Darwin.close(handle.ipcFD)
                Darwin.kill(handle.pid, SIGTERM)
            #endif
        }

        activeProcesses.removeAll()

        // Final reap
        var status: Int32 = 0
        #if canImport(Glibc)
            while Glibc.waitpid(-1, &status, WNOHANG) > 0 {
                // Reap all zombies
            }
        #elseif canImport(Darwin)
            while Darwin.waitpid(-1, &status, WNOHANG) > 0 {
                // Reap all zombies
            }
        #endif
    }

    deinit {
        // Clean up in destructor
        // Note: This runs on arbitrary thread, be careful
        for (_, handle) in activeProcesses {
            #if canImport(Glibc)
                Glibc.close(handle.ipcFD)
                Glibc.kill(handle.pid, SIGKILL)
            #elseif canImport(Darwin)
                Darwin.close(handle.ipcFD)
                Darwin.kill(handle.pid, SIGKILL)
            #endif
        }
    }
}
