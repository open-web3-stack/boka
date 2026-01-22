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
        fileDescriptor = fd
    }

    /// Close the file descriptor
    func close() {
        if let fd = fileDescriptor {
            Glibc.close(fd)
            fileDescriptor = nil
        }
    }

    /// Send an execute request and wait for response
    func sendExecuteRequest(
        blob: Data,
        pc: UInt32,
        gas: UInt64,
        argumentData: Data?,
        executionMode: ExecutionMode
    ) async throws -> (exitReason: ExitReason, gasUsed: UInt64, outputData: Data?) {
        // ⚠️ Offload blocking I/O to DispatchQueue to avoid blocking Swift concurrency pool
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: IPCError.malformedMessage)
                    return
                }
                do {
                    let result = try self.sendExecuteRequestBlocking(
                        blob: blob,
                        pc: pc,
                        gas: gas,
                        argumentData: argumentData,
                        executionMode: executionMode
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
        executionMode: ExecutionMode
    ) throws -> (exitReason: ExitReason, gasUsed: UInt64, outputData: Data?) {
        guard let fd = fileDescriptor else {
            throw IPCError.malformedMessage
        }

        // Generate request ID
        requestIdCounter = requestIdCounter &+ 1
        let requestId = requestIdCounter

        // Create and send request
        let requestData = try IPCProtocol.createExecuteRequest(
            requestId: requestId,
            blob: blob,
            pc: pc,
            gas: gas,
            argumentData: argumentData,
            executionMode: executionMode
        )

        try writeData(requestData, to: fd)

        // Wait for response (blocking)
        let responseMessage = try readMessageBlocking(requestId: requestId, from: fd)

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
            outputData: response.outputData
        )
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

    /// Read message from file descriptor (DEPRECATED: use readMessageBlocking instead)
    /// ⚠️ WARNING: Blocking I/O in async context
    /// This function is kept for backward compatibility but should not be used.
    /// Use readMessageBlocking which is called via DispatchQueue offloading instead.
    private func readMessage(requestId: UInt32, from fd: Int32) async throws -> IPCMessage {
        // Delegate to the blocking version
        return try readMessageBlocking(requestId: requestId, from: fd)
    }

    /// Read message from file descriptor (blocking version for DispatchQueue offloading)
    private func readMessageBlocking(requestId: UInt32, from fd: Int32) throws -> IPCMessage {
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

        // Verify request ID - reject mismatched responses
        guard message.requestId == requestId else {
            logger.error("Received response for different request ID (expected: \(requestId), got: \(message.requestId))")
            throw IPCError.invalidResponse("Request ID mismatch: expected \(requestId), got \(message.requestId)")
        }

        return message
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
