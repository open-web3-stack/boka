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

        isRunning = true

        while isRunning {
            do {
                // Read message
                let message = try await readMessage(from: fd)

                // Handle based on message type
                switch message.type {
                case .executeRequest:
                    await handleExecuteRequest(message, handler: handler)

                case .heartbeat:
                    // Respond to heartbeat
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
                logger.error("IPC server error: \(error)")
                isRunning = false
            }
        }
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
        // Read length prefix (4 bytes)
        let lengthData = try readExactBytes(IPCProtocol.lengthPrefixSize, from: fd)

        let length = lengthData.withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        }

        guard length > 0 && length < 1024 * 1024 * 100 else {
            throw IPCError.malformedMessage
        }

        // Read message payload
        let messageData = try readExactBytes(Int(length), from: fd)

        // Decode message
        let decodeResult = try? IPCProtocol.decodeMessage(lengthData + messageData)
        guard let message = decodeResult?.0 else {
            throw IPCError.decodingFailed("Failed to decode IPC message")
        }

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
                    Glibc.write(fd, $0, totalBytes - bytesWritten)
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
        var buffer = Data(count: count)
        var bytesRead = 0

        while bytesRead < count {
            try buffer.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddr = rawBuffer.baseAddress else {
                    throw IPCError.readFailed(Int(EINVAL))
                }

                let ptr = baseAddr.advanced(by: bytesRead)
                let result = ptr.withMemoryRebound(to: UInt8.self, capacity: count - bytesRead) {
                    Glibc.read(fd, $0, count - bytesRead)
                }

                if result < 0 {
                    let err = errno
                    // EINTR: Interrupted system call - retry the read
                    if err == EINTR {
                        return
                    }
                    logger.error("Failed to read from IPC: \(errnoToString(err))")
                    throw IPCError.readFailed(Int(err))
                }

                if result == 0 {
                    throw IPCError.unexpectedEOF
                }

                bytesRead += Int(result)

                return
            }
        }

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
        // Swift's Glibc module imports the GNU version, so we get a char* return.
        // However, on musl-based systems (Alpine Linux), the C library uses XSI
        // and the function returns Int32.
        //
        // We handle this by always checking the buffer first (both variants write to it),
        // then using the returned pointer if available (GNU variant).
        #if os(Linux)
        // Linux: Try GNU variant first, fall back to buffer
        let result = strerror_r(err, &buffer, buffer.count)

        // GNU version returns char* (may be static string or our buffer)
        // If result is nil or invalid, use buffer directly (XSI variant)
        if let ptr = result, ptr != UnsafeMutablePointer<Int8>(bitPattern: 0xFFFFFFFF) {
            // Check if pointer points to our buffer or static memory
            // GNU version: use the returned pointer
            return String(cString: ptr)
        } else {
            // XSI version or error: buffer was populated
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
