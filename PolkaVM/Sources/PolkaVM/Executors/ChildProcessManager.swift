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

    /// Mark an FD close-on-exec to prevent descriptor leakage into spawned children.
    /// Leaked parent IPC FDs can keep peer sockets alive and delay EOF detection.
    private func setCloseOnExec(fd: Int32) {
        let currentFlags = fcntl(fd, F_GETFD)
        guard currentFlags >= 0 else {
            logger.warning("Failed to read FD flags for \(fd): \(errno)")
            return
        }

        let result = fcntl(fd, F_SETFD, currentFlags | FD_CLOEXEC)
        if result != 0 {
            logger.warning("Failed to set FD_CLOEXEC for \(fd): \(errno)")
        }
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

            // Block SIGPIPE during fork/child spawn to prevent termination
            // SIGPIPE will be handled as EPIPE error on write() instead
            var blockSet = sigset_t()
            sigemptyset(&blockSet)
            sigaddset(&blockSet, SIGPIPE)
            var oldSet = sigset_t()
            pthread_sigmask(SIG_BLOCK, &blockSet, &oldSet)
            defer {
                // Restore original signal mask
                _ = pthread_sigmask(SIG_SETMASK, &oldSet, nil)
            }

            // Create socket pair for IPC
            var sockets: [Int32] = [0, 0]

            // Use raw constants to avoid Linux/Darwin type signature differences.
            let domain: Int32 = 1 // AF_UNIX
            let socketType: Int32 = 1 // SOCK_STREAM

            let result = Glibc.socketpair(domain, socketType, 0, &sockets)

            guard result == 0 else {
                let err = errno
                logger.error("Failed to create socketpair: \(err)")
                throw IPCError.writeFailed(Int(err))
            }

            let parentFD = sockets[0]
            let childFD = sockets[1]

            setCloseOnExec(fd: parentFD)
            setCloseOnExec(fd: childFD)

            logger.debug("Created socketpair: parentFD=\(parentFD), childFD=\(childFD)")

            // Validate both FDs are valid
            let parentFlags = fcntl(parentFD, F_GETFL)
            let childFlags = fcntl(childFD, F_GETFL)
            logger.debug("Socketpair validation: parentFD flags=\(parentFlags), childFD flags=\(childFlags)")

            // Convert executable path to null-terminated C string array BEFORE fork
            // This is async-signal-safe and avoids unsafe withCString in child after fork
            let execPathCArray = executablePath.utf8CString

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

                // Block SIGPIPE in child to prevent termination on broken pipe
                // This must be done before execvp to persist after process image replacement
                var childBlockSet = sigset_t()
                sigemptyset(&childBlockSet)
                sigaddset(&childBlockSet, SIGPIPE)
                var childOldSet = sigset_t()
                pthread_sigmask(SIG_BLOCK, &childBlockSet, &childOldSet)

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
                // Use pre-allocated C string array (async-signal-safe)
                // withUnsafeBufferPointer is safe here because we're in the child process
                // and the array lives until execvp replaces the process image
                execPathCArray.withUnsafeBufferPointer { buffer in
                    let execPath = buffer.baseAddress!
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

                // Wait for child to initialize and become ready
                // In release mode, processes start faster so we need longer wait
                // Also validate FD is still valid before returning
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms

                // Validate parentFD is still valid after wait
                let fdFlagsAfterWait = fcntl(parentFD, F_GETFL)
                if fdFlagsAfterWait == -1 {
                    let err = errno
                    logger.error("Parent: parentFD \(parentFD) became invalid during spawn wait: \(err)")
                    // Try to reap the child process
                    var status: Int32 = 0
                    _ = Glibc.waitpid(pid, &status, WNOHANG)
                    throw IPCError.writeFailed(Int(err))
                }

                logger.debug("Parent: Child ready, returning handle and parentFD \(parentFD) to caller")
                return (handle, parentFD)
            }
        #elseif os(macOS)
            logger.debug("Spawning child process: \(executablePath)")

            // Create socket pair for IPC
            var sockets: [Int32] = [0, 0]
            let domain: Int32 = 1 // AF_UNIX
            let socketType: Int32 = 1 // SOCK_STREAM

            let socketResult = Darwin.socketpair(domain, socketType, 0, &sockets)
            guard socketResult == 0 else {
                let err = errno
                logger.error("Failed to create socketpair: \(err)")
                throw IPCError.writeFailed(Int(err))
            }

            let parentFD = sockets[0]
            let childFD = sockets[1]

            setCloseOnExec(fd: parentFD)
            setCloseOnExec(fd: childFD)

            logger.debug("Created socketpair: parentFD=\(parentFD), childFD=\(childFD)")

            var fileActions: posix_spawn_file_actions_t?
            let initResult = posix_spawn_file_actions_init(&fileActions)
            guard initResult == 0 else {
                Darwin.close(parentFD)
                Darwin.close(childFD)
                logger.error("Failed to initialize posix_spawn file actions: \(initResult)")
                throw IPCError.writeFailed(Int(initResult))
            }

            defer {
                _ = posix_spawn_file_actions_destroy(&fileActions)
            }

            var actionResult = posix_spawn_file_actions_addclose(&fileActions, parentFD)
            guard actionResult == 0 else {
                Darwin.close(parentFD)
                Darwin.close(childFD)
                logger.error("Failed to add close action for parentFD: \(actionResult)")
                throw IPCError.writeFailed(Int(actionResult))
            }

            actionResult = posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_RDWR, 0)
            guard actionResult == 0 else {
                Darwin.close(parentFD)
                Darwin.close(childFD)
                logger.error("Failed to add stdout redirection action: \(actionResult)")
                throw IPCError.writeFailed(Int(actionResult))
            }

            actionResult = posix_spawn_file_actions_adddup2(&fileActions, childFD, STDIN_FILENO)
            guard actionResult == 0 else {
                Darwin.close(parentFD)
                Darwin.close(childFD)
                logger.error("Failed to add dup2 action for IPC stdin: \(actionResult)")
                throw IPCError.writeFailed(Int(actionResult))
            }

            actionResult = posix_spawn_file_actions_addclose(&fileActions, childFD)
            guard actionResult == 0 else {
                Darwin.close(parentFD)
                Darwin.close(childFD)
                logger.error("Failed to add close action for childFD: \(actionResult)")
                throw IPCError.writeFailed(Int(actionResult))
            }

            var pid: pid_t = 0
            var execPathCArray = executablePath.utf8CString
            let spawnResult = execPathCArray.withUnsafeMutableBufferPointer { buffer -> Int32 in
                guard let execPath = buffer.baseAddress else {
                    return EINVAL
                }

                var argv: [UnsafeMutablePointer<CChar>?] = [execPath, nil]
                return posix_spawnp(&pid, execPath, &fileActions, nil, &argv, environ)
            }

            guard spawnResult == 0 else {
                Darwin.close(parentFD)
                Darwin.close(childFD)
                logger.error("Failed to spawn child process: \(spawnResult)")
                throw IPCError.writeFailed(Int(spawnResult))
            }

            Darwin.close(childFD)

            let handle = ProcessHandle(pid: pid, ipcFD: parentFD)
            activeProcesses[pid] = handle

            logger.debug("Spawned child process: PID \(pid), returning parentFD \(parentFD)")

            // Wait for child to initialize and become ready
            // In release mode, processes start faster so we need longer wait
            // Also validate FD is still valid before returning
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms

            // Validate parentFD is still valid after wait
            let fdFlagsAfterWait = fcntl(parentFD, F_GETFL)
            if fdFlagsAfterWait == -1 {
                let err = errno
                logger.error("Parent: parentFD \(parentFD) became invalid during spawn wait: \(err)")
                throw IPCError.writeFailed(Int(err))
            }

            logger.debug("Parent: Child ready, returning handle and parentFD \(parentFD) to caller")
            return (handle, parentFD)
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
