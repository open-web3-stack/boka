import Foundation
import TracingUtils
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

private let logger = Logger(label: "IPCServer")

/// IPC server for child process to receive requests and send responses
public class IPCServer {
    private var fileDescriptor: Int32?
    private var isRunning = false

    public init() {}

    /// Set the file descriptor for communication
    public func setFileDescriptor(_ fd: Int32) {
        fileDescriptor = fd
    }

    /// Close the file descriptor
    public func close() {
        isRunning = false
        if let fd = fileDescriptor {
            #if canImport(Glibc)
                Glibc.close(fd)
            #elseif canImport(Darwin)
                Darwin.close(fd)
            #endif
            fileDescriptor = nil
        }
    }

    /// Run the IPC server loop
    public func run(handler: @escaping @Sendable (IPCExecuteRequest) async throws -> IPCExecuteResponse) async {
        guard let fd = fileDescriptor else {
            logger.error("No file descriptor set")
            return
        }

        logger.trace("[IPC-SERVER] Starting server run loop with FD \(fd)")

        // Validate FD before starting
        let flags = fcntl(fd, F_GETFL)
        if flags == -1 {
            logger.error("[IPC-SERVER] FD \(fd) is INVALID at start: \(errnoToString(errno))")
            return
        } else {
            logger.trace("[IPC-SERVER] FD \(fd) is valid at start (flags: \(flags))")
        }

        isRunning = true
        var iterationCount = 0

        while isRunning {
            iterationCount += 1
            logger.trace("[IPC-SERVER] Iteration \(iterationCount): About to read message from FD \(fd)")

            do {
                // Read message
                logger.trace("[IPC-SERVER] Calling readMessage()...")
                let message = try await readMessage(from: fd)
                logger.trace("[IPC-SERVER] Successfully read message type: \(message.type), requestId: \(message.requestId)")

                // Handle based on message type
                switch message.type {
                case .executeRequest:
                    logger.trace("[IPC-SERVER] Handling execute request")
                    await handleExecuteRequest(message, handler: handler)
                    logger.trace("[IPC-SERVER] Execute request handling complete")

                case .heartbeat:
                    // Respond to heartbeat
                    logger.trace("[IPC-SERVER] Received heartbeat, sending response")
                    let response = IPCMessage(type: .heartbeat, requestId: message.requestId)
                    try? writeMessage(response, to: fd)

                case .error:
                    logger.error("Received error message from host")
                    // Stop running on error
                    isRunning = false

                default:
                    logger.warning("Unknown message type: \(message.type)")
                }

            } catch {
                logger.error("[IPC-SERVER] IPC server error on iteration \(iterationCount): \(error)")

                // Check if FD is still valid
                let fdFlags = fcntl(fd, F_GETFL)
                if fdFlags == -1 {
                    logger.error("[IPC-SERVER] FD \(fd) became INVALID after error: \(errnoToString(errno))")
                }

                isRunning = false
            }
        }

        logger.trace("[IPC-SERVER] Server run loop exiting after \(iterationCount) iterations")
    }

    /// Handle execute request
    private func handleExecuteRequest(
        _ message: IPCMessage,
        handler: @escaping (IPCExecuteRequest) async throws -> IPCExecuteResponse
    ) async {
        guard let fd = fileDescriptor else {
            return
        }

        do {
            // Parse request
            let request = try IPCProtocol.parseExecuteRequest(message)

            // Execute request
            let response = try await handler(request)

            // Send response
            let responseData = try IPCProtocol.createExecuteResponse(
                requestId: message.requestId,
                exitReason: response.toExitReason(),
                gasUsed: response.gasUsed,
                outputData: response.outputData,
                errorMessage: response.errorMessage
            )

            try writeData(responseData, to: fd)

        } catch {
            logger.error("Failed to handle execute request: \(error)")

            // Send error response - critical to notify host of failures
            do {
                let errorMsg = try IPCProtocol.createErrorMessage(
                    requestId: message.requestId,
                    errorType: .execution,
                    message: "\(error)"
                )
                do {
                    try writeData(errorMsg, to: fd)
                } catch {
                    // If we can't send the error message, log and close the connection
                    logger.error("Failed to send error message to host: \(error)")
                    isRunning = false
                }
            } catch {
                logger.error("Failed to create error message: \(error)")
                // If we can't even create the error message, we have no choice but to close
                isRunning = false
            }
        }
    }

    /// Read message from file descriptor
    private func readMessage(from fd: Int32) async throws -> IPCMessage {
        logger.trace("[IPC-SERVER] readMessage: Reading length prefix (\(IPCProtocol.lengthPrefixSize) bytes) from FD \(fd)")

        // Read length prefix (4 bytes)
        let lengthData = try readExactBytes(IPCProtocol.lengthPrefixSize, from: fd)
        logger.trace("[IPC-SERVER] readMessage: Successfully read length prefix")

        let length = lengthData.withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        }
        logger.trace("[IPC-SERVER] readMessage: Message length: \(length) bytes")

        guard length > 0, length < 1024 * 1024 * 100 else {
            logger.error("[IPC-SERVER] readMessage: Invalid length \(length)")
            throw IPCError.malformedMessage
        }

        // Read message payload
        logger.trace("[IPC-SERVER] readMessage: Reading message payload (\(length) bytes)")
        let messageData = try readExactBytes(Int(length), from: fd)
        logger.trace("[IPC-SERVER] readMessage: Successfully read message payload")

        // Decode message
        let decodeResult = try? IPCProtocol.decodeMessage(lengthData + messageData)
        guard let message = decodeResult?.0 else {
            logger.error("[IPC-SERVER] readMessage: Failed to decode message")
            throw IPCError.decodingFailed("Failed to decode IPC message")
        }

        logger.trace("[IPC-SERVER] readMessage: Successfully decoded message, type: \(message.type)")
        return message
    }

    /// Write message to file descriptor
    private func writeMessage(_ message: IPCMessage, to fd: Int32) throws {
        let data = try IPCProtocol.encodeMessage(message)
        try writeData(data, to: fd)
    }

    /// Write data to file descriptor
    private func writeData(_ data: Data, to fd: Int32) throws {
        _ = try data.withUnsafeBytes { rawBuffer in
            guard let baseAddr = rawBuffer.baseAddress else {
                throw IPCError.writeFailed(Int(EINVAL))
            }

            var bytesWritten = 0
            let totalBytes = rawBuffer.count

            while bytesWritten < totalBytes {
                let ptr = baseAddr.advanced(by: bytesWritten)
                let result = ptr.withMemoryRebound(to: UInt8.self, capacity: totalBytes - bytesWritten) {
                    #if canImport(Glibc)
                        Glibc.write(fd, $0, totalBytes - bytesWritten)
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
                    logger.error("Failed to write to IPC: \(errnoToString(err))")
                    throw IPCError.writeFailed(Int(err))
                }

                bytesWritten += Int(result)
            }

            return bytesWritten
        }
    }

    /// Read exact number of bytes from file descriptor
    private func readExactBytes(_ count: Int, from fd: Int32) throws -> Data {
        logger.trace("[IPC-SERVER] readExactBytes: Reading \(count) bytes from FD \(fd)")

        var buffer = Data(count: count)
        var bytesRead = 0

        while bytesRead < count {
            try buffer.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddr = rawBuffer.baseAddress else {
                    logger.error("[IPC-SERVER] readExactBytes: Failed to get buffer address")
                    throw IPCError.readFailed(Int(EINVAL))
                }

                let ptr = baseAddr.advanced(by: bytesRead)
                let bytesToRead = count - bytesRead

                logger.trace("[IPC-SERVER] readExactBytes: Calling read() for \(bytesToRead) bytes (already read: \(bytesRead)/\(count))")

                let result = ptr.withMemoryRebound(to: UInt8.self, capacity: count - bytesRead) {
                    #if canImport(Glibc)
                        Glibc.read(fd, $0, count - bytesRead)
                    #elseif canImport(Darwin)
                        Darwin.read(fd, $0, count - bytesRead)
                    #endif
                }

                logger.trace("[IPC-SERVER] readExactBytes: read() returned \(result)")

                if result < 0 {
                    let err = errno
                    // EINTR: Interrupted system call - retry the read
                    if err == EINTR {
                        logger.trace("[IPC-SERVER] readExactBytes: Got EINTR, retrying")
                        return
                    }
                    logger.error("[IPC-SERVER] readExactBytes: Failed to read: \(errnoToString(err))")
                    throw IPCError.readFailed(Int(err))
                }

                if result == 0 {
                    logger.error("[IPC-SERVER] readExactBytes: Got EOF (read returned 0) - expected \(count) bytes but got \(bytesRead)")
                    throw IPCError.unexpectedEOF
                }

                bytesRead += Int(result)
                logger.trace("[IPC-SERVER] readExactBytes: Read progress: \(bytesRead)/\(count) bytes")
            }
        }

        logger.trace("[IPC-SERVER] readExactBytes: Successfully read all \(count) bytes")
        return buffer
    }

    /// Convert errno to string (thread-safe)
    private func errnoToString(_ err: Int32) -> String {
        var buffer = [Int8](repeating: 0, count: 256)

        // Use strerror_r for thread safety
        // On Linux, strerror_r has two variants:
        // - GNU (glibc): returns char* pointer to error string
        // - XSI (musl): returns Int32 (0 on success, error code on failure)
        //
        // Swift's Glibc module imports the GNU version signature, but the actual
        // implementation depends on the C library (glibc vs musl).
        //
        // CRITICAL: On XSI-compliant systems (musl), strerror_r returns Int32,
        // which Swift treats as a pointer. If this Int32 is small (e.g., EINVAL=22),
        // it becomes an invalid memory address causing crashes.
        //
        // Solution: Validate the "pointer" is actually a valid memory address
        // before dereferencing. Valid addresses are either:
        // 1. Pointing to our buffer (check address range)
        // 2. Pointing to static memory (high address > 4096)
        #if os(Linux)
            let result = strerror_r(err, &buffer, buffer.count)

            // Check if result is a valid pointer (GNU version) or error code (XSI version)
            if let ptr = result {
                // Get the numeric address value via UInt for correct bitPattern conversion
                let addr = Int(bitPattern: UInt(bitPattern: ptr))

                // Valid pointers are either:
                // - Our buffer (stack address, typically very high)
                // - Static string (data segment, > 4096)
                // Invalid: XSI error codes are small positive integers (1-4095)
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
            // macOS/BSD: XSI version, returns Int32
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
