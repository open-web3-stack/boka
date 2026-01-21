import Foundation
import TracingUtils
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

private let logger = Logger(label: "IPCClient")

/// IPC client for host process to communicate with sandboxed child process
class IPCClient {
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

        // Wait for response
        let responseMessage = try await readMessage(requestId: requestId, from: fd)

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
                    logger.error("Failed to write to IPC: \(errnoToString(err))")
                    throw IPCError.writeFailed(Int(err))
                }

                bytesWritten += Int(result)
            }

            return bytesWritten
        }
    }

    /// Read message from file descriptor
    private func readMessage(requestId: UInt32, from fd: Int32) async throws -> IPCMessage {
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

        // Verify request ID
        if message.requestId != requestId {
            logger.warning("Received response for different request ID (expected: \(requestId), got: \(message.requestId))")
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
        // GNU version: returns Int* (pointer to buffer on success, NULL on error)
        let result = strerror_r(err, &buffer, buffer.count)
        if result != nil {
            return String(cString: &buffer)
        } else {
            return "Unknown error \(err)"
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
