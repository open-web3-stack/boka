import Foundation
import TracingUtils
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

private let logger = Logger(label: "IPCClient")

/// IPC client for host process to communicate with sandboxed child process
///
/// NOTE: This class uses `@unchecked Sendable` because:
/// - It's only used for the duration of a single request
/// - The DispatchQueue offloading ensures no concurrent access
/// - All state is either immutable or locally synchronized
final class IPCClient: @unchecked Sendable {
    private var fileDescriptor: Int32?
    private var requestIdCounter: UInt32 = 0
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 30.0) {
        self.timeout = timeout
    }

    /// Set the file descriptor for communication
    func setFileDescriptor(_ fd: Int32) {
        logger.trace("[IPC] Setting file descriptor: \(fd)")

        // Validate FD is valid using fcntl
        let flags = fcntl(fd, F_GETFL)
        if flags == -1 {
            let err = errno
            logger.error("[IPC] File descriptor \(fd) is INVALID: \(errnoToString(err))")
        } else {
            logger.trace("[IPC] File descriptor \(fd) is valid (flags: \(flags))")
        }

        fileDescriptor = fd
    }

    /// Close the file descriptor
    func close() {
        if let fd = fileDescriptor {
            #if canImport(Glibc)
                Glibc.close(fd)
            #elseif canImport(Darwin)
                Darwin.close(fd)
            #endif
            fileDescriptor = nil
        }
    }

    /// Send an execute request and wait for response
    func sendExecuteRequest(
        blob: Data,
        pc: UInt32,
        gas: UInt64,
        argumentData: Data?,
        executionMode: ExecutionMode,
    ) async throws -> (exitReason: ExitReason, gasUsed: UInt64, outputData: Data?) {
        // ⚠️ Offload blocking I/O to DispatchQueue to avoid blocking Swift concurrency pool
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: IPCError.malformedMessage)
                    return
                }
                do {
                    let result = try sendExecuteRequestBlocking(
                        blob: blob,
                        pc: pc,
                        gas: gas,
                        argumentData: argumentData,
                        executionMode: executionMode,
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Synchronous blocking version for DispatchQueue offloading
    private func sendExecuteRequestBlocking(
        blob: Data,
        pc: UInt32,
        gas: UInt64,
        argumentData: Data?,
        executionMode: ExecutionMode,
    ) throws -> (exitReason: ExitReason, gasUsed: UInt64, outputData: Data?) {
        guard let fd = fileDescriptor else {
            logger.error("[IPC] No file descriptor set")
            throw IPCError.malformedMessage
        }
        let deadline = DispatchTime.now() + timeout

        let timestamp = Date().timeIntervalSince1970
        logger.trace("[IPC][\(timestamp)] Using file descriptor: \(fd)")

        // Validate FD is still valid before writing
        let flags = fcntl(fd, F_GETFL)
        if flags == -1 {
            let err = errno
            logger.error("[IPC][\(timestamp)] File descriptor \(fd) is INVALID before write: \(errnoToString(err))")
            throw IPCError.writeFailed(Int(err))
        } else {
            logger.trace("[IPC][\(timestamp)] File descriptor \(fd) is valid before write (flags: \(flags))")
        }

        // Generate request ID
        requestIdCounter = requestIdCounter &+ 1
        let requestId = requestIdCounter
        logger.trace("[IPC][\(timestamp)] Sending request \(requestId), blob size: \(blob.count)")

        // Create and send request
        let requestData = try IPCProtocol.createExecuteRequest(
            requestId: requestId,
            blob: blob,
            pc: pc,
            gas: gas,
            argumentData: argumentData,
            executionMode: executionMode,
        )

        logger.trace("[IPC][\(timestamp)] Writing \(requestData.count) bytes to FD \(fd)")
        try writeData(requestData, to: fd, deadline: deadline)
        logger.trace("[IPC][\(timestamp)] Write completed successfully")

        // Wait for response (blocking)
        let responseMessage = try readMessageBlocking(requestId: requestId, from: fd, deadline: deadline)

        // Parse response
        let response = try IPCProtocol.parseExecuteResponse(responseMessage)

        // Check for errors
        if let errorMessage = response.errorMessage {
            logger.error("Child process error: \(errorMessage)")
            throw IPCError.childProcessError(errorMessage)
        }

        return (
            exitReason: response.toExitReason(),
            gasUsed: response.gasUsed,
            outputData: response.outputData,
        )
    }

    /// Write data to file descriptor
    private func writeData(_ data: Data, to fd: Int32, deadline: DispatchTime) throws {
        _ = try data.withUnsafeBytes { rawBuffer in
            guard let baseAddr = rawBuffer.baseAddress else {
                throw IPCError.writeFailed(Int(EINVAL))
            }

            var bytesWritten = 0
            let totalBytes = rawBuffer.count

            while bytesWritten < totalBytes {
                do {
                    try waitForFileDescriptor(fd, events: Int16(POLLOUT), deadline: deadline)
                } catch IPCError.unexpectedEOF {
                    throw IPCError.brokenPipe
                }

                let ptr = baseAddr.advanced(by: bytesWritten)
                let result = ptr.withMemoryRebound(to: UInt8.self, capacity: totalBytes - bytesWritten) {
                    #if canImport(Glibc)
                        #if os(Linux)
                            // Avoid process-level SIGPIPE on closed socket FDs. We want EPIPE instead.
                            Glibc.send(fd, $0, totalBytes - bytesWritten, Int32(MSG_NOSIGNAL))
                        #else
                            Glibc.write(fd, $0, totalBytes - bytesWritten)
                        #endif
                    #elseif canImport(Darwin)
                        Darwin.write(fd, $0, totalBytes - bytesWritten)
                    #endif
                }

                if result < 0 {
                    let err = errno
                    // EINTR: Interrupted system call - retry the write
                    if err == EINTR {
                        continue
                    }
                    // Retry if socket temporarily can't accept writes.
                    if err == EAGAIN || err == EWOULDBLOCK {
                        continue
                    }
                    // EPIPE: Broken pipe - child has closed its end
                    // This is expected when worker process terminates
                    if err == EPIPE {
                        logger.warning("IPC write failed: Broken pipe (EPIPE) - worker process may have terminated")
                        throw IPCError.brokenPipe
                    }
                    logger.error("Failed to write to IPC: \(errnoToString(err))")
                    throw IPCError.writeFailed(Int(err))
                }

                bytesWritten += Int(result)
            }

            return bytesWritten
        }
    }

    /// Read message from file descriptor (DEPRECATED: use readMessageBlocking instead)
    /// ⚠️ WARNING: Blocking I/O in async context
    /// This function is kept for backward compatibility but should not be used.
    /// Use readMessageBlocking which is called via DispatchQueue offloading instead.
    private func readMessage(requestId: UInt32, from fd: Int32) async throws -> IPCMessage {
        // Delegate to the blocking version
        let deadline = DispatchTime.now() + timeout
        return try readMessageBlocking(requestId: requestId, from: fd, deadline: deadline)
    }

    /// Read message from file descriptor (blocking version for DispatchQueue offloading)
    private func readMessageBlocking(requestId: UInt32, from fd: Int32, deadline: DispatchTime) throws -> IPCMessage {
        // Read length prefix (4 bytes)
        let lengthData = try readExactBytes(IPCProtocol.lengthPrefixSize, from: fd, deadline: deadline)

        let length = lengthData.withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        }

        guard length > 0, length < 1024 * 1024 * 100 else {
            throw IPCError.malformedMessage
        }

        // Read message payload
        let messageData = try readExactBytes(Int(length), from: fd, deadline: deadline)

        // Decode message
        let decodeResult = try? IPCProtocol.decodeMessage(lengthData + messageData)
        guard let message = decodeResult?.0 else {
            throw IPCError.decodingFailed("Failed to decode IPC message")
        }

        // Verify request ID - reject mismatched responses
        guard message.requestId == requestId else {
            logger.error("Received response for different request ID (expected: \(requestId), got: \(message.requestId))")
            throw IPCError.invalidResponse("Request ID mismatch: expected \(requestId), got \(message.requestId)")
        }

        return message
    }

    /// Read exact number of bytes from file descriptor
    private func readExactBytes(_ count: Int, from fd: Int32, deadline: DispatchTime) throws -> Data {
        var buffer = Data(count: count)
        var bytesRead = 0

        while bytesRead < count {
            try waitForFileDescriptor(fd, events: Int16(POLLIN), deadline: deadline)

            try buffer.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddr = rawBuffer.baseAddress else {
                    throw IPCError.readFailed(Int(EINVAL))
                }

                let ptr = baseAddr.advanced(by: bytesRead)
                let result = ptr.withMemoryRebound(to: UInt8.self, capacity: count - bytesRead) {
                    #if canImport(Glibc)
                        Glibc.read(fd, $0, count - bytesRead)
                    #elseif canImport(Darwin)
                        Darwin.read(fd, $0, count - bytesRead)
                    #endif
                }

                if result < 0 {
                    let err = errno
                    // EINTR: Interrupted system call - retry the read
                    if err == EINTR {
                        return
                    }
                    // Retry if socket temporarily has no bytes available.
                    if err == EAGAIN || err == EWOULDBLOCK {
                        return
                    }
                    logger.error("Failed to read from IPC: \(errnoToString(err))")
                    throw IPCError.readFailed(Int(err))
                }

                if result == 0 {
                    throw IPCError.unexpectedEOF
                }

                bytesRead += Int(result)
            }
        }

        return buffer
    }

    private func waitForFileDescriptor(_ fd: Int32, events: Int16, deadline: DispatchTime) throws {
        var pollDescriptor = pollfd(fd: fd, events: events, revents: 0)

        while true {
            guard let timeoutMilliseconds = remainingPollTimeoutMilliseconds(until: deadline) else {
                throw IPCError.timeout
            }

            #if canImport(Glibc)
                let result = Glibc.poll(&pollDescriptor, 1, timeoutMilliseconds)
            #elseif canImport(Darwin)
                let result = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
            #endif

            if result == 0 {
                throw IPCError.timeout
            }

            if result < 0 {
                let err = errno
                if err == EINTR {
                    continue
                }
                throw IPCError.readFailed(Int(err))
            }

            if pollDescriptor.revents & Int16(POLLNVAL) != 0 {
                throw IPCError.readFailed(Int(EBADF))
            }

            if pollDescriptor.revents & Int16(POLLERR) != 0 {
                throw IPCError.readFailed(Int(EIO))
            }

            if pollDescriptor.revents & Int16(POLLHUP) != 0,
               pollDescriptor.revents & events == 0
            {
                throw IPCError.unexpectedEOF
            }

            if pollDescriptor.revents & events != 0 {
                return
            }
        }
    }

    private func remainingPollTimeoutMilliseconds(until deadline: DispatchTime) -> Int32? {
        let now = DispatchTime.now().uptimeNanoseconds
        let deadlineNanos = deadline.uptimeNanoseconds
        guard deadlineNanos > now else {
            return nil
        }

        let remainingNanos = deadlineNanos - now
        let milliseconds = remainingNanos / 1_000_000
        if milliseconds == 0 {
            return 1
        }

        return Int32(min(milliseconds, UInt64(Int32.max)))
    }

    /// Convert errno to string (thread-safe)
    private func errnoToString(_ err: Int32) -> String {
        var buffer = [Int8](repeating: 0, count: 256)
        // Use strerror_r for thread safety
        #if os(Linux)
            let result = strerror_r(err, &buffer, buffer.count)

            // Check if result is a valid pointer (GNU version) or error code (XSI version)
            // Valid pointers are either:
            // 1. Pointing to our buffer (stack address, typically very high)
            // 2. Pointing to static memory (high address > 4096)
            // Invalid: XSI error codes are small positive integers (1-4095)
            if let ptr = result {
                // Get the numeric address value via UInt for correct bitPattern conversion
                let addr = Int(bitPattern: UInt(bitPattern: ptr))

                if addr > 4096 {
                    // Valid pointer: use it (GNU version)
                    return String(cString: ptr)
                } else {
                    // Invalid pointer: must be XSI error code, use buffer
                    // Buffer was populated even on error in XSI version
                    return String(cString: &buffer)
                }
            } else {
                // nil result: use buffer
                return String(cString: &buffer)
            }
        #else
            // XSI version (macOS): returns Int32 (0 on success, error code on failure)
            let result = strerror_r(err, &buffer, buffer.count)
            if result == 0 {
                return String(cString: &buffer)
            } else {
                return "Unknown error \(err)"
            }
        #endif
    }

    deinit {
        close()
    }
}
