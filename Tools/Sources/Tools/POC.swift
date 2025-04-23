import ArgumentParser
import CTools
import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

// Helper function for logging to standard error
func log(_ message: String) {
    fputs(message + "\n", stderr)
}

// MARK: - IPC Message Protocol

enum IPCMessage: UInt32 {
    case run = 0x0000_0001
    case done = 0x0000_0002
    case exit = 0x0000_0003

    @discardableResult
    func write(to fd: FileHandle) -> Result<Void, Error> {
        var rawValue = rawValue
        return Result {
            try fd.write(contentsOf: Data(bytes: &rawValue, count: MemoryLayout<UInt32>.size))
            _ = try? fd.synchronize()
        }
    }

    static func read(from fd: FileHandle) -> Result<IPCMessage, Error> {
        Result {
            let data = try fd.read(upToCount: MemoryLayout<UInt32>.size)
            if let data, let decoded = IPCMessage(rawValue: data.withUnsafeBytes { $0.load(as: UInt32.self) }) {
                return decoded
            }
            throw POCError.invalidIPCMessage(data: data)
        }
    }
}

// MARK: - Error Handling

enum POCError: Error, CustomStringConvertible {
    case shmOpenFailed(errno: Int32)
    case shmTruncateFailed(errno: Int32)
    case mmapFailed(errno: Int32)
    case childProcessFailed(error: Error)
    case ipcReadFailed(errno: Int32)
    case invalidIPCMessage(data: Data?)

    var description: String {
        switch self {
        case let .shmOpenFailed(errno):
            "Failed to open shared memory: \(String(cString: strerror(errno)))"
        case let .shmTruncateFailed(errno):
            "Failed to set shared memory size: \(String(cString: strerror(errno)))"
        case let .mmapFailed(errno):
            "Failed to map memory: \(String(cString: strerror(errno)))"
        case let .childProcessFailed(error):
            "Failed to spawn child process: \(error)"
        case let .ipcReadFailed(errno):
            "Failed to read IPC message: \(String(cString: strerror(errno)))"
        case let .invalidIPCMessage(value):
            "Received invalid IPC message: \(String(describing: value))"
        }
    }
}

struct POC: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "POC tools")

    @Flag var worker: Bool = false
    @Option var shmName: String = "/poc_recompiler_shm"

    func run() async throws {
        if worker {
            try runChildMode(shmName: shmName)
        } else {
            try runParentMode(shmName: shmName)
        }
    }
}

// MARK: - Configuration

private let SHM_SIZE = 4096
private let CODE_OFFSET = 0
private let DATA_OFFSET = 1024
private let CODE_SIZE = 8 // size of generated stub on AArch64

// We'll pass IPC channels on these file descriptor numbers in the child.
private let IPC_READ_FD: Int32 = 3 // Child will read commands from here
private let IPC_WRITE_FD: Int32 = 4 // Child will write responses here

// MARK: - Child Entry Point

func runChildMode(shmName: String) throws {
    log("[Child] Starting child mode…")
    // Use dedicated IPC FDs (3 and 4) rather than standard in/out.
    let pipeInFD = FileHandle(fileDescriptor: IPC_READ_FD)
    let pipeOutFD = FileHandle(fileDescriptor: IPC_WRITE_FD)

    // 1) Open shared memory.
    let shmFD = ctools_shm_open(shmName, O_RDWR, 0o600)
    if shmFD < 0 {
        throw POCError.shmOpenFailed(errno: errno)
    }
    log("[Child] Shared memory opened successfully with FD: \(shmFD)")

    // 2) Map shared memory for IPC data only
    let childMap = mmap(nil, SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, shmFD, 0)
    guard childMap != MAP_FAILED else {
        throw POCError.mmapFailed(errno: errno)
    }
    log("[Child] Shared memory mapped successfully at address: \(childMap!)")

    // 3) Allocate a separate JIT region for executing injected code
    let codeMap = mmap(
        nil,
        SHM_SIZE, PROT_READ | PROT_WRITE | PROT_EXEC,
        MAP_ANON | MAP_PRIVATE | MAP_JIT,
        -1,
        0
    )
    guard codeMap != MAP_FAILED else {
        throw POCError.mmapFailed(errno: errno)
    }

    log("[Child] JIT region allocated successfully at address: \(codeMap!)")

    // Copy generated machine code from shared memory into JIT buffer
    pthread_jit_write_protect_np(0)
    memcpy(codeMap, childMap!.advanced(by: CODE_OFFSET), CODE_SIZE)

    log("[Child] Code copied to JIT region")

    sys_icache_invalidate(codeMap, Int(SHM_SIZE))
    pthread_jit_write_protect_np(1)

    log("[Child] JIT region invalidated")

    // 3) Listen for IPC messages on the dedicated FDs.
    outer:
        while true
    {
        log("[Child] Waiting for IPC message on fd: \(pipeInFD)")
        let messageResult = IPCMessage.read(from: pipeInFD)
        log("[Child] Received IPC message: \(messageResult)")

        switch messageResult {
        case let .success(message):
            switch message {
            case .run:
                let codePtr = codeMap!
                typealias FuncType = @convention(c) (UInt64, UInt64) -> UInt64
                let fn: FuncType = unsafeBitCast(codePtr, to: FuncType.self)

                // Read operands from shared memory
                let op1 = childMap!.advanced(by: DATA_OFFSET + 12).loadUnaligned(as: UInt64.self)
                let op2 = childMap!.advanced(by: DATA_OFFSET + 20).loadUnaligned(as: UInt64.self)

                log("[Child] Executing code function with operands \(op1) and \(op2)")
                let res = fn(op1, op2)
                log("[Child] Function returned \(res)")

                // Store the result back to shared memory at offset +4 (keeping the original layout)
                childMap!.advanced(by: DATA_OFFSET + 4).storeBytes(of: res, as: UInt64.self)

                log("[Child] Executed code function, sending DONE response")
                try IPCMessage.done.write(to: pipeOutFD).get()
                log("[Child] DONE response sent")
            case .exit:
                log("[Child] Received EXIT command, terminating child mode")
                break outer
            default:
                log("[Child] Received unexpected message: \(message)")
            }
        case let .failure(error):
            log("[Child] Error: \(error)")
            break outer
        }
    }

    munmap(codeMap, SHM_SIZE)
    munmap(childMap, SHM_SIZE)
    close(shmFD)
}

// MARK: - Parent Entry Point (Using posix_spawn with Extra IPC FDs)

func runParentMode(shmName: String) throws {
    print("[Parent] Starting parent mode…")

    // Create two pipes: one for sending commands to the child and one for receiving responses.
    let inputPipe = Pipe() // Parent writes; child reads.
    let outputPipe = Pipe() // Child writes; parent reads.
    print("[Parent] Pipes created for IPC.")

    // 1) Create and configure shared memory.
    shm_unlink(shmName) // Remove any existing shared memory.
    let shmFD = ctools_shm_open(shmName, O_CREAT | O_RDWR, 0o600)
    if shmFD < 0 {
        throw POCError.shmOpenFailed(errno: errno)
    }
    print("[Parent] Shared memory created with FD: \(shmFD)")
    if ftruncate(shmFD, off_t(SHM_SIZE)) != 0 {
        throw POCError.shmTruncateFailed(errno: errno)
    }
    print("[Parent] Shared memory truncated to \(SHM_SIZE) bytes")

    guard let parentMap = mmap(nil, SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, shmFD, 0) else {
        throw POCError.mmapFailed(errno: errno)
    }
    if parentMap == MAP_FAILED {
        throw POCError.mmapFailed(errno: errno)
    }
    print("[Parent] Memory mapped at address: \(parentMap)")

    // 2) Spawn the child process using posix_spawn with file actions.
    // Instead of modifying STDIN/STDOUT, we'll map the IPC pipes to FDs 3 and 4.
    print("[Parent] Launching child process with posix_spawn")

    let childIpcReadFD = inputPipe.fileHandleForReading.fileDescriptor // For child: will be dup'd to FD 3.
    let childIpcWriteFD = outputPipe.fileHandleForWriting.fileDescriptor // For child: will be dup'd to FD 4.

    // Keep parent's write end (for inputPipe) and read end (for outputPipe) for IPC.
    let parentInputWriteFD = inputPipe.fileHandleForWriting.fileDescriptor
    let parentOutputReadFD = outputPipe.fileHandleForReading.fileDescriptor

    var fileActions = posix_spawn_file_actions_t(bitPattern: 0)
    posix_spawn_file_actions_init(&fileActions)

    // Duplicate the required descriptors into the child on FDs 3 and 4.
    posix_spawn_file_actions_adddup2(&fileActions, childIpcReadFD, IPC_READ_FD)
    posix_spawn_file_actions_adddup2(&fileActions, childIpcWriteFD, IPC_WRITE_FD)
    // Close parent's ends in the child.
    // posix_spawn_file_actions_addclose(&fileActions, parentInputWriteFD)
    // posix_spawn_file_actions_addclose(&fileActions, parentOutputReadFD)

    let executable = CommandLine.arguments[0]
    let arg0 = executable
    let arg1 = "poc"
    let arg2 = "--worker"
    let arg3 = "--shm-name=\(shmName)"

    var args: [UnsafeMutablePointer<CChar>?] = [
        strdup(arg0),
        strdup(arg1),
        strdup(arg2),
        strdup(arg3),
        nil,
    ]

    var pid: pid_t = 0
    let spawnResult = posix_spawn(&pid, executable, &fileActions, nil, &args, environ)
    posix_spawn_file_actions_destroy(&fileActions)

    // Free the C strings.
    for arg in args {
        if let arg { free(arg) }
    }

    if spawnResult != 0 {
        let errMsg = String(cString: strerror(spawnResult))
        throw POCError.childProcessFailed(error: NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(spawnResult),
            userInfo: [NSLocalizedDescriptionKey: errMsg]
        ))
    }
    print("[Parent] Child process spawned with pid: \(pid)")

    // 3) Initialize shared memory data and emit code.
    let codePtr = parentMap + CODE_OFFSET
    let dataPtr = parentMap + DATA_OFFSET
    (dataPtr + 0).storeBytes(of: UInt32(0), as: UInt32.self)
    (dataPtr + 4).storeBytes(of: UInt64(0), as: UInt64.self)
    (dataPtr + 12).storeBytes(of: UInt64(10), as: UInt64.self)
    (dataPtr + 20).storeBytes(of: UInt64(32), as: UInt64.self)
    print("[Parent] Data layout initialized: operands 10 and 32")

    let codeSize = emitAddExample(codePtr)
    print("[Parent] Add example code emitted (\(codeSize) bytes) at codePtr: \(codePtr)")

    mprotect(parentMap, SHM_SIZE, PROT_READ | PROT_EXEC)
    print("[Parent] Memory protection updated to READ+EXEC")

    // 4) Use the parent's ends of the pipes to communicate.
    print("[Parent] Sending RUN command to child")
    let runResult = IPCMessage.run.write(to: FileHandle(fileDescriptor: parentInputWriteFD))
    if case let .failure(error) = runResult {
        throw error
    }
    print("[Parent] RUN command sent")

    print("[Parent] Waiting for child's response")
    let responseResult = IPCMessage.read(from: FileHandle(fileDescriptor: parentOutputReadFD))
    switch responseResult {
    case let .success(message):
        if message == .done {
            print("[Parent] Child responded with DONE")
        } else {
            print("[Parent] Child sent unexpected response: \(message)")
        }
    case let .failure(error):
        print("[Parent] Failed to read response: \(error)")
        throw error
    }

    let result = (dataPtr + 4).load(as: UInt32.self)
    print("[Parent] Sum result = \(result) (expected 42)")

    print("[Parent] Sending EXIT command to child")
    let exitResult = IPCMessage.exit.write(to: FileHandle(fileDescriptor: parentInputWriteFD))
    if case let .failure(error) = exitResult {
        print("[Parent] Failed to send EXIT command: \(error)")
    }
    print("[Parent] EXIT command sent, proceeding with cleanup")

    munmap(parentMap, SHM_SIZE)
    close(shmFD)
    print("[Parent] Cleanup complete; waiting for child to exit")

    var status: Int32 = 0
    waitpid(pid, &status, 0)
    print("[Parent] Child exit code: \(status)")
}
