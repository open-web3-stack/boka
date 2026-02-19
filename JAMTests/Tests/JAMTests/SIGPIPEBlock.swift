#if os(Linux)
    import Glibc
    import Foundation

    /// Block SIGPIPE at module load time to prevent test process termination
    /// on broken pipe errors during IPC communication with sandbox processes.
    ///
    /// When a sandbox process crashes or times out, it closes its IPC socket.
    /// If the test process tries to write to this closed socket, SIGPIPE would
    /// normally terminate the entire test process. By blocking SIGPIPE, write()
    /// calls return EPIPE error instead, which is already handled gracefully by
    /// the IPC code.
    private func blockSIGPIPE() {
        var blockSet = sigset_t()
        sigemptyset(&blockSet)
        sigaddset(&blockSet, SIGPIPE)
        var oldSet = sigset_t()
        pthread_sigmask(SIG_BLOCK, &blockSet, &oldSet)
    }

    /// Execute at module load time - BEFORE any tests run.
    /// This uses the same pattern as the sandbox (PolkaVM/Sources/Sandbox/main.swift)
    /// which has been proven to work reliably in all build configurations.
    private let _blockSIGPIPE: Void = {
        blockSIGPIPE()
        return ()
    }()
#endif
